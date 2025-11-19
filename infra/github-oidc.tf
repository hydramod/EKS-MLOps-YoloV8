resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub's thumbprint - this is static and correct as of 2024
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-github-oidc-provider"
    }
  )
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Format: "repo:GITHUB_ORG/REPO_NAME:*"
            "token.actions.githubusercontent.com:sub" = "repo:hydramod/EKS-MLOps-YoloV8:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-github-actions-role"
    }
  )
}

# Attach AdministratorAccess policy (for full infrastructure management)
# NOTE: In production, you should use more restrictive policies
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Optional: Create a more restrictive custom policy instead
resource "aws_iam_policy" "github_actions_custom" {
  count = var.use_custom_policy ? 1 : 0

  name        = "${var.project_name}-github-actions-policy"
  description = "Custom policy for GitHub Actions with limited permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # ECR permissions
          "ecr:*",
          # EKS permissions
          "eks:*",
          # EC2 permissions (for VPC, subnets, etc.)
          "ec2:*",
          # IAM permissions (for roles, policies)
          "iam:*",
          # S3 permissions (for Terraform state)
          "s3:*",
          # DynamoDB permissions (for Terraform locking)
          "dynamodb:*",
          # Route53 permissions
          "route53:*",
          # CloudWatch Logs
          "logs:*",
          # Auto Scaling
          "autoscaling:*",
          # Elastic Load Balancing
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_custom" {
  count = var.use_custom_policy ? 1 : 0

  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_custom[0].arn
}

# Outputs
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.name
}

output "setup_instructions" {
  description = "Instructions for setting up GitHub Actions"
  value       = <<-EOT
    
    ========================================
    GitHub Actions Setup Complete!
    ========================================
    
    1. Add this secret to your GitHub repository:
       
       Secret Name: AWS_ROLE_TO_ASSUME
       Secret Value: ${aws_iam_role.github_actions.arn}
    
    2. Go to: https://github.com/YOUR_ORG/YOUR_REPO/settings/secrets/actions
    
    3. Click "New repository secret"
    
    4. Your GitHub Actions workflows are now ready to use!
    
    ========================================
  EOT
}
