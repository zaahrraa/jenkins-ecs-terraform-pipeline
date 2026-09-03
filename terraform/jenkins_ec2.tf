# ---------- DATA SOURCE: Latest Amazon Linux AMI ----------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
# ---------- JENKINS MASTER ----------
resource "aws_instance" "jenkins_master" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type # t2.micro is fine with swap!
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y

    # 1. Install Java 21, Docker, Git
    dnf install -y java-21-amazon-corretto docker git

    # 2. Start Docker
    systemctl enable docker && systemctl start docker
    usermod -aG docker ec2-user

    # 3. Add swap space (CRITICAL for t2.micro!)
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

    # 4. Download and install Jenkins directly (no GPG issues!)
    wget -O /tmp/jenkins.deb https://get.jenkins.io/debian-stable/jenkins_2.568.1_all.deb
    dpkg -i /tmp/jenkins.deb || dnf install -y net-tools

    # 5. Set JAVA_HOME for Jenkins
    echo "JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto" | tee -a /etc/default/jenkins

    # 6. Set temp directory to avoid disk space issues
    mkdir -p /var/lib/jenkins/tmp
    chown jenkins:jenkins /var/lib/jenkins/tmp
    echo 'JAVA_ARGS="-Djava.awt.headless=true -Djava.io.tmpdir=/var/lib/jenkins/tmp"' >> /etc/default/jenkins

    # 7. Start Jenkins
    systemctl enable jenkins && systemctl start jenkins

    # 8. Add Jenkins to Docker group
    usermod -aG docker jenkins
    systemctl restart jenkins

    # 9. Clean up temp files to save space
    rm -rf /tmp/jenkins*.deb
    dnf clean all
  EOF

  tags = { Name = "${var.project_name}-jenkins-master" }
}

# ---------- JENKINS AGENT ----------
resource "aws_instance" "jenkins_agent" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type # t2.micro is fine with swap!
  subnet_id              = aws_subnet.public[1].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y

    # 1. Install Java 21, Docker, Git
    dnf install -y java-21-amazon-corretto docker git

    # 2. Start Docker
    systemctl enable docker && systemctl start docker
    usermod -aG docker ec2-user

    # 3. Add swap (agents also need memory!)
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
  EOF

  tags = { Name = "${var.project_name}-jenkins-agent" }
}