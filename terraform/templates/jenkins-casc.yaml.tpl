jenkins:
  systemMessage: "Provisioned automatically by Terraform -- do not add nodes manually."
  numExecutors: 0
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "${admin_user}"
          password: "${admin_password}"
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false
  nodes:
    - permanent:
        name: "docker-agent"
        remoteFS: "/home/ec2-user/agent"
        numExecutors: 2
        labelString: "docker-agent"
        launcher:
          ssh:
            host: "${agent_private_ip}"
            port: 22
            credentialsId: "agent-ssh-key"
            sshHostKeyVerificationStrategy:
              nonVerifyingKeyVerificationStrategy: {}
        retentionStrategy: "always"

credentials:
  system:
    domainCredentials:
      - credentials:
          - basicSSHUserPrivateKey:
              scope: GLOBAL
              id: "agent-ssh-key"
              username: "ec2-user"
              description: "SSH key for docker-agent"
              privateKeySource:
                directEntry:
                  privateKey: |
                    ${indent(24, chomp(agent_ssh_private_key))}
          - string:
              scope: GLOBAL
              id: "github-token-id"
              secret: "${github_token}"
              description: "GitHub PAT for API requests and branch indexing"
          - usernamePassword:
              scope: GLOBAL
              id: "github-token-userpass"
              username: "zaahrraa"
              password: "${github_token}"
              description: "GitHub PAT (username+password form) for branch source scanning"

jobs:
  - script: >
      multibranchPipelineJob('my-app-pipeline') {
          description('Auto-provisioned via Terraform and JCasC')
          branchSources {
              github {
                  id('jenkins-ecs-pipeline-repo')
                  scanCredentialsId('github-token-userpass')
                  repoOwner('zaahrraa')
                  repository('jenkins-ecs-terraform-pipeline')
              }
          }
          factory {
              workflowBranchProjectFactory {
                  scriptPath('Jenkinsfile')
              }
          }
          triggers {
              periodicFolderTrigger {
                  interval('5m')
              }
          }
          orphanedItemStrategy {
              discardOldItems {
                  numToKeep(5)
              }
          }
      }

unclassified:
  gitHubPluginConfig:
    configs:
      - name: "GitHub"
        apiUrl: "https://api.github.com"
        credentialsId: "github-token-id"
        manageHooks: false