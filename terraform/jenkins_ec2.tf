# ---------- DATA SOURCE: Latest Amazon Linux AMI ----------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ---------- LOCALS: Render templates ----------
locals {
  agent_ssh_private_key = file("${path.module}/../${var.key_pair_name}.pem")
  jenkins_plugins_txt   = file("${path.module}/../jenkins/plugins.txt")

  # JCasC YAML configuration
  jenkins_casc_yaml = templatefile("${path.module}/templates/jenkins-casc.yaml.tpl", {
    admin_user              = var.jenkins_admin_user
    admin_password          = var.jenkins_admin_password
    agent_private_ip        = aws_instance.jenkins_agent.private_ip
    agent_ssh_private_key = local.agent_ssh_private_key
  })

  # Master user data
  master_user_data = templatefile("${path.module}/templates/jenkins-master-user-data.sh.tpl", {
    jenkins_casc_yaml   = base64encode(local.jenkins_casc_yaml)
    jenkins_plugins_txt = base64encode(local.jenkins_plugins_txt)
    agent_private_ip    = aws_instance.jenkins_agent.private_ip
  })

  # Agent user data
  agent_user_data = templatefile("${path.module}/templates/jenkins-agent-user-data.sh.tpl", {})
}

# ---------- JENKINS MASTER ----------
resource "aws_instance" "jenkins_master" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  user_data_replace_on_change = true
  user_data                   = local.master_user_data

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

  user_data_replace_on_change = true
  user_data                   = local.agent_user_data

  tags = { Name = "${var.project_name}-jenkins-agent" }
}