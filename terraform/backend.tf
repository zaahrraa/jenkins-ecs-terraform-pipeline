# Use your unique bucket name - replace "your-unique-name"
terraform {
  backend "s3" {
    bucket         = "jenkins-pipeline-s3-state-xyz789"
    key            = "jenkins-ecs/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}