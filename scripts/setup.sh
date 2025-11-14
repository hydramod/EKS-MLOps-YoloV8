#!/bin/bash

# YOLOv8 MLOps Setup Script
# This script helps automate the initial setup

set -e

echo "=================================="
echo "YOLOv8 MLOps Setup Script"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}Checking prerequisites...${NC}"

    MISSING_DEPS=0

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ AWS CLI not found${NC}"
        MISSING_DEPS=1
    else
        echo -e "${GREEN}✓ AWS CLI installed${NC}"
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}✗ Terraform not found${NC}"
        MISSING_DEPS=1
    else
        echo -e "${GREEN}✓ Terraform installed${NC}"
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl not found${NC}"
        MISSING_DEPS=1
    else
        echo -e "${GREEN}✓ kubectl installed${NC}"
    fi

    # Check Helm
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}✗ Helm not found${NC}"
        MISSING_DEPS=1
    else
        echo -e "${GREEN}✓ Helm installed${NC}"
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker not found${NC}"
        MISSING_DEPS=1
    else
        echo -e "${GREEN}✓ Docker installed${NC}"
    fi

    if [ $MISSING_DEPS -eq 1 ]; then
        echo -e "\n${RED}Some prerequisites are missing. Please install them first.${NC}"
        exit 1
    fi
}

# Get user inputs
get_inputs() {
    echo -e "\n${YELLOW}Configuration${NC}"

    read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    read -p "Enter AWS region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}

    read -p "Enter project name [yolov8-mlops]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-yolov8-mlops}

    echo -e "\n${GREEN}Configuration:${NC}"
    echo "  Domain: $DOMAIN_NAME"
    echo "  Region: $AWS_REGION"
    echo "  Project: $PROJECT_NAME"

    read -p "Continue? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo "Aborted."
        exit 0
    fi
}

# Create AWS resources
create_aws_resources() {
    echo -e "\n${YELLOW}Creating AWS resources...${NC}"

    # Get AWS account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "AWS Account ID: $ACCOUNT_ID"

    # Create S3 bucket for Terraform state
    echo -e "\n${YELLOW}Creating S3 bucket for Terraform state...${NC}"
    aws s3 mb s3://${PROJECT_NAME}-terraform-state --region $AWS_REGION || true
    aws s3api put-bucket-versioning \
        --bucket ${PROJECT_NAME}-terraform-state \
        --versioning-configuration Status=Enabled

    echo -e "${GREEN}✓ S3 bucket created${NC}"

    # Create DynamoDB table for state locking
    echo -e "\n${YELLOW}Creating DynamoDB table for state locking...${NC}"
    aws dynamodb create-table \
        --table-name terraform-state-lock \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region $AWS_REGION 2>/dev/null || echo "Table may already exist"

    echo -e "${GREEN}✓ DynamoDB table ready${NC}"
}

# Update configuration files
update_configs() {
    echo -e "\n${YELLOW}Updating configuration files...${NC}"

    # Create terraform.tfvars
    cat > infra/terraform.tfvars <<EOF
aws_region  = "$AWS_REGION"
environment = "production"
project_name = "$PROJECT_NAME"

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]

cluster_version          = "1.28"
node_group_instance_types = ["t3.medium"]
node_group_desired_size  = 2
node_group_min_size      = 1
node_group_max_size      = 4

domain_name = "$DOMAIN_NAME"
subdomain   = "ml"

backend_image_tag  = "latest"
frontend_image_tag = "latest"
EOF

    echo -e "${GREEN}✓ terraform.tfvars created${NC}"

    # Export variables
    export DOMAIN_NAME
    export AWS_REGION
    export PROJECT_NAME
    export ACCOUNT_ID

    # Create env file
    cat > .env <<EOF
DOMAIN_NAME=$DOMAIN_NAME
AWS_REGION=$AWS_REGION
PROJECT_NAME=$PROJECT_NAME
ACCOUNT_ID=$ACCOUNT_ID
EOF

    echo -e "${GREEN}✓ .env file created${NC}"
}

# Main execution
main() {
    check_prerequisites
    get_inputs
    create_aws_resources
    update_configs

    echo -e "\n${GREEN}=================================="
    echo "Setup Complete!"
    echo "==================================${NC}"

    echo -e "\nNext steps:"
    echo "1. Update your domain nameservers with Route 53 NS records"
    echo "2. cd infra && terraform init"
    echo "3. terraform plan"
    echo "4. terraform apply"
    echo -e "\nSee QUICKSTART.md for detailed deployment steps."
}

main
