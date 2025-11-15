# Quick Start Guide

This guide helps you get the YOLOv8 MLOps application running quickly.

## Prerequisites Checklist

- [ ] AWS account with admin access
- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.5.0 installed
- [ ] kubectl >= 1.28 installed
- [ ] Helm >= 3.13 installed
- [ ] Docker installed (for local testing)
- [ ] Domain name registered
- [ ] GitHub account

## 6-Step Deployment

### Step 0: Bootstrap State Backend (5 minutes - FIRST TIME ONLY)

Before any infrastructure deployment, bootstrap the Terraform state backend:

```bash
# Automated bootstrap
./scripts/bootstrap.sh
```

This creates S3 bucket and DynamoDB table for Terraform state management.

**Alternatively, use the combined setup script:**
```bash
./scripts/setup.sh
# This will prompt you to run bootstrap automatically
```

### Step 1: Prepare AWS (10 minutes)

```bash
# Set your domain and region
export DOMAIN_NAME="yourdomain.com"
export AWS_REGION="us-east-1"
export PROJECT_NAME="yolov8-mlops"

# Create Route 53 hosted zone
aws route53 create-hosted-zone \
  --name $DOMAIN_NAME \
  --caller-reference $(date +%s)

# Note the name servers and update your domain registrar
<<<<<<< HEAD
=======

# Create S3 bucket for Terraform state
aws s3 mb s3://${PROJECT_NAME}-terraform-state --region $AWS_REGION
aws s3api put-bucket-versioning \
  --bucket ${PROJECT_NAME}-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION
>>>>>>> test_branch
```

### Step 2: Configure Terraform (5 minutes)

```bash
# Clone repository
git clone <your-repo-url>
cd ECS-MLOPS-

# Update Terraform variables
cd infra
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
nano terraform.tfvars
# Change:
# - domain_name = "yourdomain.com"
# - aws_region (if different)
```

### Step 3: Deploy Infrastructure (20 minutes)

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (takes ~15-20 minutes)
terraform apply -auto-approve

# Configure kubectl
aws eks update-kubeconfig --region $AWS_REGION --name ${PROJECT_NAME}-production-eks
```

### Step 4: Build and Push Images (10 minutes)

```bash
# Get your AWS account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push backend
cd ../app/backend
docker build -t yolov8-backend .
docker tag yolov8-backend:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest

# Build and push frontend
cd ../frontend
docker build -t yolov8-frontend .
docker tag yolov8-frontend:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest
```

### Step 5: Deploy Application (10 minutes)

```bash
# Deploy with Helm
cd ../../charts/yolov8
helm upgrade --install yolov8 . \
  --namespace yolov8 \
  --create-namespace \
  --set global.domain=$DOMAIN_NAME \
  --set global.subdomain=ml \
  --set backend.image.repository=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend \
  --set backend.image.tag=latest \
  --set frontend.image.repository=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend \
  --set frontend.image.tag=latest \
  --wait \
  --timeout 10m

# Check deployment
kubectl get pods -n yolov8
kubectl get ingress -n yolov8
```

## Verification

### Check Application Status

```bash
# Verify all pods are running
kubectl get pods -n yolov8

# Check ingress
kubectl get ingress -n yolov8

# Wait for DNS (5-10 minutes)
watch -n 5 "dig ml.$DOMAIN_NAME +short"

# Test health endpoint
curl https://ml.$DOMAIN_NAME/health
```

### Access Application

Open your browser: `https://ml.yourdomain.com`

Upload a test image and verify object detection works!

## Cleanup

To destroy all resources and stop charges:

```bash
# Delete Helm release
helm uninstall yolov8 -n yolov8

# Destroy infrastructure
cd infra
terraform destroy -auto-approve
```

## Troubleshooting

**Pods not starting?**
```bash
kubectl describe pod <pod-name> -n yolov8
kubectl logs <pod-name> -n yolov8
```

**DNS not resolving?**
```bash
# Check ExternalDNS
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Verify Route53 records
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

**Certificate issues?**
```bash
kubectl get certificate -n yolov8
kubectl describe certificate yolov8-tls -n yolov8
```

## Next Steps

1. Set up GitHub Actions for CI/CD
2. Configure monitoring with Prometheus/Grafana
3. Implement custom domain logic
4. Add authentication
5. Scale for production load

## Cost Warning

This setup costs approximately **$265/month**. Remember to destroy resources when not in use!

## Support

- Check the main README.md for detailed documentation
- Review troubleshooting section
- Open GitHub issues for problems
