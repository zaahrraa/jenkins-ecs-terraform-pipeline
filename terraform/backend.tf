terraform {
  backend "s3" {
    bucket         = "jenkins-tf-state-1788615755"   # ← Update this!
    key            = "jenkins-ecs/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}