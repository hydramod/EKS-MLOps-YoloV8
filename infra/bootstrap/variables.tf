variable "bucket_name" {
  description = "S3 Bucket name"
  type        = string
  default     = "eks-mlops-alistechlab"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for state locking"
  type        = string
  default     = "eks-mlops-terraform-locks"
}
