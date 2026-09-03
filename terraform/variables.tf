variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource tagging"
  default     = "jenkins-ecs-pipeline"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"  # Free tier eligible
}

variable "key_pair_name" {
  description = "Name of existing EC2 key pair for SSH access"
}

variable "my_ip" {
  description = "Your public IP address for SSH access (format: x.x.x.x/32)"
}