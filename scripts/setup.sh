#!/bin/bash

# YOLOv8 MLOps Setup Script
# This script helps automate the initial setup

set -e

# Load environment variables from .env if it exists
if [ -f .env ]; then
    echo "Loading environment from .env file..."
    set -a
    source .env
    set +a
fi

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

    # Domain name (use env var as default if set)
    if [ -n "$DOMAIN_NAME" ]; then
        read -p "Enter your domain name [$DOMAIN_NAME]: " INPUT_DOMAIN_NAME
        DOMAIN_NAME=${INPUT_DOMAIN_NAME:-$DOMAIN_NAME}
    else
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    fi

    # AWS region (use env var as default if set)
    DEFAULT_AWS_REGION=${AWS_REGION:-us-east-1}
    read -p "Enter AWS region [$DEFAULT_AWS_REGION]: " INPUT_AWS_REGION
    AWS_REGION=${INPUT_AWS_REGION:-$DEFAULT_AWS_REGION}

    # Project name (use env var as default if set)
    DEFAULT_PROJECT_NAME=${PROJECT_NAME:-yolov8-mlops}
    read -p "Enter project name [$DEFAULT_PROJECT_NAME]: " INPUT_PROJECT_NAME
    PROJECT_NAME=${INPUT_PROJECT_NAME:-$DEFAULT_PROJECT_NAME}

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

# Run bootstrap for state backend
run_bootstrap() {
    echo -e "\n${YELLOW}Bootstrap State Backend${NC}"
    echo "The Terraform state backend (S3 + DynamoDB) must be created first."
    echo ""

    read -p "Do you want to run the bootstrap now? (y/n): " RUN_BOOTSTRAP

    if [ "$RUN_BOOTSTRAP" == "y" ]; then
        echo -e "\n${YELLOW}Running bootstrap...${NC}"
        ./scripts/bootstrap.sh
    else
        echo -e "${YELLOW}Skipping bootstrap. Make sure to run it manually:${NC}"
        echo "  ./scripts/bootstrap.sh"
        echo ""
        read -p "Press Enter to continue..."
    fi
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

    # Get AWS Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

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
    run_bootstrap
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
