variable "aws_region" {
  description = "AWS region for the state backend resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "yolov8-mlops"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state storage"
  type        = string
  default     = "yolov8-mlops-terraform-state"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.state_bucket_name))
    error_message = "Bucket name must be lowercase alphanumeric with hyphens."
  }
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "yolov8-mlops-terraform-lock"
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "state_retention_days" {
  description = "Number of days to retain old state file versions"
  type        = number
  default     = 90
}
