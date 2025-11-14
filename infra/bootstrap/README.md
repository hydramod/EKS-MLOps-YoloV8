# Terraform State Backend Bootstrap

This directory contains the Terraform configuration for bootstrapping the remote state backend infrastructure. This must be deployed **before** the main infrastructure.

## Overview

The bootstrap creates:
- **S3 Bucket** - Stores Terraform state files with versioning and encryption
- **S3 Bucket (Logs)** - Stores access logs for the state bucket
- **DynamoDB Table** - Provides state locking to prevent concurrent modifications
- **IAM Policy** - Grants appropriate access permissions to the state backend

## Why Bootstrap?

Terraform needs a place to store its state file. For production environments, this should be:
- Remote (not local)
- Versioned (to track changes and enable rollback)
- Encrypted (to protect sensitive data)
- Locked (to prevent concurrent modifications)

The bootstrap uses **local state** to create these resources, then the main infrastructure uses **remote state** stored in S3.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0 installed
- AWS account with permissions to create S3, DynamoDB, and IAM resources

## Usage

### Step 1: Configure Variables

Create a `terraform.tfvars` file from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and customize the values:

```hcl
aws_region          = "us-east-1"
project_name        = "yolov8-mlops"
state_bucket_name   = "your-unique-bucket-name"  # MUST BE GLOBALLY UNIQUE!
dynamodb_table_name = "yolov8-mlops-terraform-lock"
```

**Important:** S3 bucket names must be globally unique across all AWS accounts. Add a prefix like your company name or a random string.

### Step 2: Initialize Terraform

```bash
cd infra/bootstrap
terraform init
```

### Step 3: Review the Plan

```bash
terraform plan
```

This will show you what resources will be created:
- 2 S3 buckets (state + logs)
- 1 DynamoDB table
- 1 IAM policy
- Various bucket configurations (versioning, encryption, etc.)

### Step 4: Apply the Configuration

```bash
terraform apply
```

Review the output and type `yes` to confirm.

### Step 5: Note the Outputs

After successful deployment, Terraform will output important information:

```bash
terraform output -json
```

You'll see:
- `state_bucket_name` - Use this in your main Terraform backend config
- `dynamodb_table_name` - Use this for state locking
- `backend_config_hcl` - Ready-to-use backend configuration

### Step 6: Update Main Infrastructure Backend

Copy the backend configuration to your main Terraform configuration:

```bash
terraform output -raw backend_config_hcl
```

Update `infra/provider.tf` with these values:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-bucket-name"
    key            = "eks-mlops/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "your-table-name"
  }
}
```

## Architecture

```
Bootstrap (Local State)
    │
    ├─► S3 Bucket (State Storage)
    │   ├─► Versioning Enabled
    │   ├─► Encryption Enabled
    │   ├─► Public Access Blocked
    │   └─► Lifecycle Rules
    │
    ├─► S3 Bucket (Logs)
    │   └─► Access Logs
    │
    ├─► DynamoDB Table (State Locking)
    │   ├─► Pay-per-request Billing
    │   ├─► Point-in-time Recovery
    │   └─► Encryption Enabled
    │
    └─► IAM Policy (Access Control)
        └─► Granular Permissions

Main Infrastructure (Remote State)
    │
    └─► Uses Bootstrap Resources ─► EKS, VPC, etc.
```

## Features

### S3 Bucket (State Storage)
- **Versioning** - Keep history of all state changes
- **Encryption** - AES256 server-side encryption
- **Public Access Block** - Prevent accidental public exposure
- **Lifecycle Rules** - Automatically delete old versions after 90 days
- **Logging** - Track all access to the state bucket

### DynamoDB Table (State Locking)
- **Pay-per-request** - Cost-effective for small teams
- **Point-in-time Recovery** - Restore table to any point in last 35 days
- **Encryption** - Server-side encryption enabled
- **Consistent Locking** - Prevent concurrent Terraform operations

### IAM Policy
- **Least Privilege** - Only necessary permissions
- **Exportable** - Can be attached to CI/CD roles or users

## Cost Estimate

The bootstrap infrastructure costs approximately:

| Resource | Monthly Cost |
|----------|--------------|
| S3 Storage (< 1 GB) | $0.03 |
| S3 Requests | $0.01 |
| DynamoDB (Pay-per-request) | $0.25 |
| **Total** | **~$0.30/month** |

## Management

### Viewing Current State

Since bootstrap uses local state, you can check it with:

```bash
terraform show
```

### Updating Bootstrap Resources

If you need to modify bootstrap resources:

```bash
terraform plan
terraform apply
```

### Destroying Bootstrap Resources

**⚠️ WARNING:** Only destroy bootstrap resources if you're sure you don't need them anymore. This will delete your Terraform state backend!

Before destroying:
1. Destroy all main infrastructure first
2. Ensure no state files exist in the S3 bucket
3. Back up important state files

```bash
# Check what will be destroyed
terraform plan -destroy

# Destroy resources
terraform destroy
```

## Security Best Practices

1. **Enable prevent_destroy** in production:
   ```hcl
   lifecycle {
     prevent_destroy = true
   }
   ```

2. **Use bucket policies** to restrict access:
   - Only allow specific IAM roles/users
   - Require MFA for deletion operations
   - Enable CloudTrail logging

3. **Backup the bootstrap state file**:
   ```bash
   cp terraform.tfstate terraform.tfstate.backup
   ```
   Store this backup securely (e.g., encrypted in 1Password, LastPass)

4. **Use separate AWS accounts** for different environments

5. **Enable AWS CloudTrail** to audit all API calls

## Troubleshooting

### Bucket Already Exists

If you get an error that the bucket already exists, either:
- Choose a different bucket name (must be globally unique)
- Import the existing bucket: `terraform import aws_s3_bucket.terraform_state bucket-name`

### Access Denied Errors

Ensure your AWS credentials have permissions to:
- Create S3 buckets and configure bucket settings
- Create DynamoDB tables
- Create IAM policies

### State File Locked

If you see a lock error:
1. Check if another Terraform operation is running
2. If stuck, manually remove the lock from DynamoDB:
   ```bash
   aws dynamodb delete-item \
     --table-name yolov8-mlops-terraform-lock \
     --key '{"LockID":{"S":"<lock-id>"}}'
   ```

## Migration from Existing Setup

If you already have S3/DynamoDB resources:

1. **Import existing resources**:
   ```bash
   terraform import aws_s3_bucket.terraform_state existing-bucket-name
   terraform import aws_dynamodb_table.terraform_state_lock existing-table-name
   ```

2. **Run terraform plan** to see what changes are needed

3. **Apply carefully** to avoid disruption

## Next Steps

After bootstrap is complete:

1. ✓ Update `infra/provider.tf` with backend configuration
2. ✓ Initialize main infrastructure: `cd ../infra && terraform init`
3. ✓ Migrate local state to remote (if applicable)
4. ✓ Deploy main infrastructure: `terraform apply`

## References

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
