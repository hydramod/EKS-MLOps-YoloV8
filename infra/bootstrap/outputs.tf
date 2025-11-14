output "bucket_name" {
  value       = aws_s3_bucket.state.bucket
  description = "S3 bucket created for Terraform backend"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.state_lock.name
  description = "DynamoDB table created for Terraform state locking"
}