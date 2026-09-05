# ---------- ECR REPOSITORY ----------
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------- ECR REPOSITORY POLICY ----------
# Grants the Jenkins EC2 role permission to push/pull images.
# Uses aws_iam_role.jenkins_role.arn (resolved dynamically) instead of a
# hardcoded account ID/ARN, so this works correctly across any AWS account
# — important for environments like KodeKloud sandboxes where the account
# changes between sessions.
resource "aws_ecr_repository_policy" "ecr_policy" {
  repository = aws_ecr_repository.app_repo.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowJenkinsPushPull"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.jenkins_role.arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}