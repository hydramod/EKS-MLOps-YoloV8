output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "state_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.region
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_state_lock.id
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_state_lock.arn
}

output "terraform_state_policy_arn" {
  description = "ARN of the IAM policy for Terraform state access"
  value       = aws_iam_policy.terraform_state_access.arn
}

output "backend_config" {
  description = "Backend configuration to use in main Terraform configuration"
  value = {
    bucket         = aws_s3_bucket.terraform_state.id
    key            = "eks-mlops/terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
    dynamodb_table = aws_dynamodb_table.terraform_state_lock.id
  }
}

output "backend_config_hcl" {
  description = "Backend configuration in HCL format for easy copy-paste"
  value = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.terraform_state.id}"
      key            = "eks-mlops/terraform.tfstate"
      region         = "${var.aws_region}"
      encrypt        = true
      dynamodb_table = "${aws_dynamodb_table.terraform_state_lock.id}"
    }
  EOT
}
