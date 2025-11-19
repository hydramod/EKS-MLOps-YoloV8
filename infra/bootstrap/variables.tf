variable "state_bucket_name" {
  description = "S3 Bucket name"
  type        = string
  default     = "eks-mlops-alistechlab"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for state locking"
  type        = string
  default     = "eks-mlops-terraform-locks"
}

variable "aws_region" {
  description = "AWS region to use"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "yolov8-mlops"
}