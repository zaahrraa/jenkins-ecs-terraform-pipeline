# Jenkins + Terraform CI/CD Pipeline to Amazon ECS

Fully automated CI/CD pipeline: **Terraform** provisions all AWS infrastructure (Jenkins master + agent, ECR, ECS Fargate, IAM, VPC, ALB) and configures Jenkins itself via **Configuration as Code (JCasC)** — no manual clicking required. **Jenkins** then builds a Dockerized Flask app, runs tests, pushes the image to ECR, and deploys it to ECS on every push to `main`.

```
git push → Jenkins builds & tests → Docker image → Amazon ECR → Amazon ECS (Fargate) → Live app behind an ALB
```

---

## Architecture

- **Networking:** Custom VPC (not the AWS default) — 2 public subnets (Jenkins, ALB) + 2 private subnets (ECS tasks) across 2 AZs, connected via a NAT Gateway. ECS tasks have no public IP; all traffic reaches them only through the ALB.
- **CI/CD:** Jenkins master + SSH-connected build agent, both on EC2. Jenkins is fully configured on first boot via JCasC — admin user, SSH agent node, GitHub credentials, and the multibranch pipeline job are all defined as code, not clicked together.
- **Containers:** Docker → Amazon ECR → Amazon ECS Fargate, fronted by an Application Load Balancer.
- **Security:** Jenkins/ECS talk to AWS via IAM instance roles — no long-lived AWS access keys stored anywhere in Jenkins or the pipeline.
- **Monitoring:** CloudWatch log group for ECS task output.

---

## Project Structure

```
jenkins-ecs-terraform-pipeline/
│
├── terraform/
│   ├── templates/
│   │   ├── jenkins-casc.yaml.tpl          # Jenkins Configuration as Code
│   │   ├── jenkins-master-user-data.sh.tpl
│   │   └── jenkins-agent-user-data.sh.tpl
│   ├── alb.tf
│   ├── backend.tf
│   ├── cloudwatch.tf
│   ├── ecr.tf
│   ├── ecs.tf
│   ├── iam.tf
│   ├── jenkins_ec2.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── security_groups.tf
│   ├── variables.tf
│   ├── vpc.tf
│   └── terraform.tfvars                   # gitignored — no secrets committed
│
├── jenkins/
│   └── plugins.txt
│
├── app/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── tests/
│       └── test_app.py
│
├── Jenkinsfile
├── screenshots/
├── .gitignore
└── README.md
```

---

## Pipeline Stages

1. **Checkout** — pull the latest commit via authenticated GitHub credential
2. **Install & Test** — `pip install`, `pytest`
3. **Build Docker Image** — tagged with both `:$BUILD_NUMBER` and `:latest`
4. **Push to ECR** — authenticated via IAM instance role, no stored AWS keys
5. **Deploy to ECS** — `aws ecs update-service --force-new-deployment`
6. **Verify Deployment**

Triggered automatically on push via a GitHub webhook (falls back to a 5-minute poll if the webhook is ever missed).

---

## 🚀 Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/zaahrraa/jenkins-ecs-terraform-pipeline.git
cd jenkins-ecs-terraform-pipeline
```

### 2. Generate SSH Key
```powershell
aws ec2 create-key-pair --key-name jenkins-key --query "KeyMaterial" --output text | Out-File -FilePath jenkins-key.pem -Encoding ascii -NoNewline
```
> ⚠️ On Windows, do **not** use `> jenkins-key.pem` redirection — PowerShell saves it as UTF-16, which breaks Terraform's `file()` function later. Use the `Out-File -Encoding ascii` form above instead.

### 3. Create S3 Backend & DynamoDB
```bash
aws s3 mb s3://jenkins-tf-state-$(date +%s) --region us-east-1
aws dynamodb create-table --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

### 4. Configure Terraform
Update `terraform/backend.tf` with your bucket name, and `terraform/terraform.tfvars` with your key pair name and public IP. Set secrets as environment variables — **never** in a committed file:
```powershell
$env:TF_VAR_jenkins_admin_password = "choose-a-strong-password"
$env:TF_VAR_github_token = "your-github-PAT"
```

### 5. Run Terraform
```bash
cd terraform
terraform init
terraform plan     # review before applying
terraform apply
```

### 6. Access Jenkins
Jenkins is fully pre-configured via JCasC on first boot — no setup wizard, no `initialAdminPassword` file to fetch. Log in directly with the admin user/password you set in step 4:
```
http://<JENKINS_IP>:8080
```
Username: `admin` (or whatever `jenkins_admin_user` is set to) · Password: whatever you set as `TF_VAR_jenkins_admin_password`

### 7. Wire Up the Pipeline
- Grab the outputs:
  ```bash
  terraform output jenkins_master_public_ip
  terraform output app_load_balancer_url
  ```
- Add a GitHub webhook pointing at `http://<jenkins_master_public_ip>:8080/github-webhook/`.
- Push to `main` and watch the pipeline run — Jenkins already has the `docker-agent` node connected and the multibranch job created, both provisioned automatically by JCasC.

To tear everything down: `terraform destroy`.

---

## Issues Faced & How They Were Solved

This project surfaced **21 distinct issues** while building a fully automated, zero-manual-steps pipeline. Grouped by category:

### Windows Environment Traps
| Issue | Root Cause | Fix |
|---|---|---|
| `.pem` key "not valid UTF-8" (hit twice) | PowerShell's `>` redirection saves UTF-16 with a BOM, not UTF-8 | Re-saved the file: `Set-Content -Encoding ascii -NoNewline` |
| `unexpected EOF while looking for matching )'` | CRLF line endings in `.tpl` files broke bash's `\` line-continuation inside `$(...)` | Converted files to LF; rewrote multi-line piped commands as single physical lines to eliminate the bug class |

### Terraform Structural Issues
| Issue | Root Cause | Fix |
|---|---|---|
| `Error: Cycle: aws_instance.jenkins_agent, ...` | Master referenced agent's IP while agent had an explicit `depends_on` back on master | Removed the redundant `depends_on` — Terraform already inferred correct order from the IP reference |
| CloudWatch log group "already exists" | State drift — resource existed in AWS but not in Terraform state | `terraform import aws_cloudwatch_log_group.ecs_logs /ecs/jenkins-ecs-pipeline` |
| `terraform destroy` failed — ECR not empty | AWS won't delete a repo containing images | Emptied the repo manually, then added `force_delete = true` |
| ECR repository policy had a hardcoded account ID | `Principal.AWS` was a literal ARN string — breaks on any account change | Replaced with `aws_iam_role.jenkins_role.arn` (dynamic reference) |

### EC2 Boot Script (`user_data`)
| Issue | Root Cause | Fix |
|---|---|---|
| Jenkins installed but never started | Hardcoded plugin-manager-tool version URL went stale; plain `curl -L` saved a 404 page as if it were a real jar; `set -e` killed the script before `systemctl start jenkins` ran | Resolved the download URL dynamically via GitHub's API, added `-f` to curl, validated the jar with `unzip -l`, moved `systemctl start jenkins` to the unconditional last line |
| `curl: Malformed input to a URL function` | `grep` matched more than one asset URL; the variable held two URLs joined by a newline | Added `head -n1` to force a single result |

### Jenkins Configuration as Code (JCasC) & Job DSL
| Issue | Root Cause | Fix |
|---|---|---|
| Agent never connects (JNLP) | Secret is generated by Jenkins *after* the node exists — can't be hardcoded ahead of time; also `user_data` only runs on first boot, so updating it later never re-applies | Abandoned JNLP for **SSH-launch**, where the master initiates the connection |
| Agent goes offline after every pipeline run | Agent launched manually via SSH as a foreground process — died on session close (`SIGHUP`) | Ran as a systemd service (`Restart=always`), later superseded entirely by SSH-launch |
| Malformed nested heredoc broke the systemd unit file | `cat > file <<EOF` nested inside Terraform's `<<-EOF` is fragile to indentation/CRLF | Stopped nesting heredocs; used `templatefile()` + base64 encoding instead |
| JCasC never created the `docker-agent` node | Terraform's `indent()` indents every line *except the first* — the private key's `BEGIN` line got 0 spaces while the rest got 18, breaking YAML's uniform-indentation rule for block scalars | Manually indented the interpolation itself so the first line matched |
| Jenkins crashed on boot — `ConfiguratorException` | Mixed JCasC-native branch-source YAML syntax (`branchSource { source { github {...} } }`) into a Job DSL script, which uses a different, flatter API | Used Job DSL's correct syntax: `branchSources { github { ...; scanCredentialsId(...) } }` |

### GitHub Integration
| Issue | Root Cause | Fix |
|---|---|---|
| Branch indexing stuck anonymous, rate-limited | Missing `plain-credentials` plugin meant the GitHub token credential silently failed to load | Added `plain-credentials`/`ssh-credentials` to `plugins.txt` |
| Still anonymous even with a working credential | Jenkins' global GitHub rate-limiter reads a separate `unclassified.gitHubPluginConfig` block, which didn't exist | Added the block, pointing it at the token credential |
| Branch source Credentials dropdown showed only "- none -" | That specific field only accepts **Username+Password** type credentials; a Secret Text credential never appears there, regardless of content | Added a second credential of type `usernamePassword:` with the same token |
| ECR push denied | Jenkins' AWS role lived in one account; `Jenkinsfile` had a hardcoded, stale account ID from a previous session | Replaced with `sh(script: 'aws sts get-caller-identity'...)` resolved at build time |
| Same ECR error recurred across two builds | The corrected Jenkinsfile existed locally but was never actually committed/pushed | Verified directly with `git show origin/main:Jenkinsfile` before re-testing — confirmed the actual fix, then committed properly |
| `git push` rejected by secret scanning | Real GitHub PAT was committed in `terraform.tfvars` | Revoked/rotated the token, removed it from the file, added it to `.gitignore`, used `git reset --soft origin/main` to safely rewrite the never-pushed commits, switched to supplying secrets via `$env:TF_VAR_...` only |
| Builds needed manual "Build Now" | No webhook configured — only a 5-minute poll | Added a GitHub webhook pointing at `/github-webhook/`; noted it needs updating whenever the master's IP changes |

---

## Troubleshooting Reference

```bash
# EC2 / boot diagnostics (run after SSHing in)
sudo systemctl status jenkins
curl -I http://localhost:8080
sudo tail -100 /var/log/cloud-init-output.log
sudo journalctl -u jenkins -n 150 --no-pager
sudo cat /var/lib/jenkins/casc_configs/jenkins.yaml

# Terraform
terraform validate
terraform plan
terraform apply -replace="aws_instance.jenkins_master"
terraform import <resource_address> <real_aws_id>
terraform force-unlock <LOCK_ID>

# Git — verify what's ACTUALLY committed before re-testing
git show origin/main:<path>
git reset --soft origin/main

# AWS
aws sts get-caller-identity                     # never hardcode an account ID — check this instead
aws ecr batch-delete-image --repository-name <repo> --region <region> --image-ids "$(aws ecr list-images ...)"
aws ecs describe-services --cluster <cluster> --services <service>
```

**Windows-specific fixes (PowerShell):**
```powershell
# Fix UTF-16/CRLF files (.pem, .tpl)
$raw = Get-Content -Path .\file -Raw
Set-Content -Path .\file -Value $raw -Encoding ascii -NoNewline

# grep isn't native — use this instead
Get-ChildItem -Recurse -Include *.tf,*.tpl,Jenkinsfile | Select-String -Pattern "pattern1|pattern2"
```

---

## Key Lessons

- **Windows encoding/line-endings** (UTF-16 `.pem` files, CRLF in shell scripts) caused more failures here than any actual logic bug — worth checking first whenever a script "looks right" but fails mysteriously.
- **JCasC and Job DSL are similar-looking but distinct APIs** — mixing their syntax fails at Jenkins boot time, not at write time, so errors only surface after a full rebuild.
- **Verify, don't assume, what's actually committed** — several rounds of "still broken" were really "still testing the old code" because a local fix was never pushed.
- **IAM instance roles over static keys** — Jenkins never stores AWS credentials directly, which also means account-ID mismatches surface as clear `AccessDenied` errors rather than silent misuse of the wrong account.