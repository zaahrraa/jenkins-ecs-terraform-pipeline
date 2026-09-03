output "jenkins_master_public_ip" {
  description = "Public IP of Jenkins master"
  value       = aws_instance.jenkins_master.public_ip
}

output "jenkins_agent_public_ip" {
  description = "Public IP of Jenkins agent"
  value       = aws_instance.jenkins_agent.public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "app_load_balancer_url" {
  description = "Load balancer URL for the application"
  value       = "http://${aws_lb.app_alb.dns_name}"
}