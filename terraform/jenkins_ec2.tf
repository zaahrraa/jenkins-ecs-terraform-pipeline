# ---------- DATA SOURCE: Latest Amazon Linux AMI ----------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ---------- LOCAL: Generate agent service file from template ----------
locals {
  agent_service_file = templatefile("${path.module}/templates/jenkins-agent.service.tpl", {
    jenkins_master_ip = aws_instance.jenkins_master.private_ip
    agent_secret      = var.agent_secret
  })
}

# ---------- JENKINS MASTER ----------
resource "aws_instance" "jenkins_master" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y

    # 1. Install dependencies
    dnf install -y java-21-amazon-corretto docker git python3 python3-pip wget

    # 2. Install pytest
    pip3 install pytest

    # 3. Start Docker
    systemctl enable docker && systemctl start docker
    usermod -aG docker ec2-user

    # 4. Add swap space
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

    # 5. Install Jenkins
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins

    # 6. Set JAVA_HOME
    echo "JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto" | tee -a /etc/default/jenkins

    # 7. Set temp directory
    mkdir -p /var/lib/jenkins/tmp
    chown jenkins:jenkins /var/lib/jenkins/tmp
    echo 'JAVA_ARGS="-Djava.awt.headless=true -Djava.io.tmpdir=/var/lib/jenkins/tmp"' >> /etc/default/jenkins

    # 8. Start Jenkins
    systemctl enable jenkins && systemctl start jenkins

    # 9. Add Jenkins to Docker group
    usermod -aG docker jenkins
    systemctl restart jenkins

    # 10. Clean up
    rm -rf /tmp/jenkins*.rpm
    dnf clean all
  EOF

  tags = { Name = "${var.project_name}-jenkins-master" }
}

# ---------- JENKINS AGENT ----------
resource "aws_instance" "jenkins_agent" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[1].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  # Automatically recreate agent when user_data changes
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y

    # 1. Install dependencies
    dnf install -y java-21-amazon-corretto docker git python3 python3-pip wget

    # 2. Install pytest
    pip3 install pytest

    # 3. Start Docker
    systemctl enable docker && systemctl start docker
    usermod -aG docker ec2-user

    # 4. Add swap space
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

    # 5. Create agent directory
    mkdir -p /home/ec2-user/agent
    chown ec2-user:ec2-user /home/ec2-user/agent

    # 6. Wait for Jenkins master to be ready
    echo "Waiting for Jenkins master to be ready..."
    sleep 30

    # 7. Download agent.jar from Jenkins master
    wget -O /home/ec2-user/agent/agent.jar http://${aws_instance.jenkins_master.private_ip}:8080/jnlpJars/agent.jar

    # 8. Create the agent service using base64-encoded template (no heredoc nesting!)
    echo "${base64encode(local.agent_service_file)}" | base64 -d > /etc/systemd/system/jenkins-agent.service

    # 9. Start and enable the agent service
    systemctl daemon-reload
    systemctl enable --now jenkins-agent
  EOF

  tags = { Name = "${var.project_name}-jenkins-agent" }
}