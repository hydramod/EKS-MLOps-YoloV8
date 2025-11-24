# Quick Start Guide

This guide helps you get the YOLOv8 MLOps application running quickly using automated scripts.

## Prerequisites Checklist

- [ ] AWS account with admin access
- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.5.0 installed
- [ ] kubectl >= 1.28 installed
- [ ] Helm >= 3.13 installed
- [ ] Docker installed
- [ ] Domain name registered
- [ ] Route 53 hosted zone created for your domain

## Fastest Deployment (3 Commands)

```bash
# 1. Setup and bootstrap
./scripts/setup.sh

# 2. Deploy infrastructure
cd infra && terraform init && terraform apply

# 3. Build and deploy application
cd .. && ./scripts/deploy.sh
```

Done! Your application will be available at `https://ml.yourdomain.com` after DNS propagation (5-10 minutes).

## Detailed 6-Step Deployment

### Step 0: Clone Repository

```bash
git clone <your-repo-url>
cd ECS-MLOPS-
```

### Step 1: Automated Setup and Bootstrap (5 minutes - FIRST TIME ONLY)

Run the interactive setup script:

```bash
./scripts/setup.sh
```

This script will:
- ✅ Validate all prerequisites (AWS CLI, Terraform, kubectl, Helm, Docker)
- ✅ Prompt for your configuration (domain name, AWS region, project name)
- ✅ Offer to run bootstrap automatically (creates S3 + DynamoDB for Terraform state)
- ✅ Create `.env` file with your configuration
- ✅ Create `infra/terraform.tfvars` with infrastructure settings
- ✅ Auto-detect your AWS account ID

**What gets created:**
- `.env` - Environment variables for scripts
- `infra/terraform.tfvars` - Terraform configuration
- `infra/bootstrap/terraform.tfvars` - Bootstrap configuration
- S3 bucket and DynamoDB table for Terraform state (if you chose to run bootstrap)

**Important:** After bootstrap completes, copy the backend configuration output and update `infra/provider.tf` (lines 24-30).

### Step 2: Prepare AWS Route 53 (5 minutes)

**If you haven't already created a Route 53 hosted zone:**

```bash
# Load your configuration
source .env

# Create Route 53 hosted zone
aws route53 create-hosted-zone \
  --name $DOMAIN_NAME \
  --caller-reference $(date +%s)

# Note the name servers from the output
# Update your domain registrar with these NS records
```

**Verify NS records are propagated:**
```bash
dig $DOMAIN_NAME NS +short
```

### Step 3: Deploy Infrastructure (20 minutes)

```bash
cd infra

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy infrastructure (takes ~15-20 minutes)
terraform apply

# Verify cluster is accessible
aws eks update-kubeconfig --region $AWS_REGION --name ${PROJECT_NAME}-production-eks
kubectl get nodes
```

**What gets created:**
- VPC with public/private subnets across 3 availability zones
- EKS cluster with managed node group (2x t3.medium instances)
- ECR repositories for backend and frontend images
- Nginx Ingress Controller
- ExternalDNS for automatic Route53 record management
- Cert-Manager for automatic TLS certificates (Let's Encrypt)
- ArgoCD for GitOps continuous deployment

### Step 4: Build and Deploy Application (15 minutes)

**🚀 Automated Option (Recommended):**

```bash
cd ..  # Return to project root
./scripts/deploy.sh
```

This script automatically:
- ✅ Configures kubectl for your EKS cluster
- ✅ Logs into AWS ECR
- ✅ Builds backend and frontend Docker images
- ✅ Pushes images to ECR repositories
- ✅ Deploys application with Helm using your .env configuration
- ✅ Verifies deployment and displays application URL

**🔧 Manual Option:**

If you prefer to run commands manually:

```bash
# Load environment
source .env

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push backend
cd app/backend
docker build -t yolov8-backend .
docker tag yolov8-backend:latest \
  ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest
docker push \
  ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest

# Build and push frontend
cd ../frontend
docker build -t yolov8-frontend .
docker tag yolov8-frontend:latest \
  ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest
docker push \
  ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest

# Deploy with Helm
cd ../..
helm upgrade --install yolov8 ./charts/yolov8 \
  --namespace yolov8 \
  --create-namespace \
  --set global.domain=$DOMAIN_NAME \
  --set global.subdomain=ml \
  --set backend.image.repository=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend \
  --set backend.image.tag=latest \
  --set frontend.image.repository=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend \
  --set frontend.image.tag=latest \
  --wait \
  --timeout 10m
```

### Step 5: Verify Deployment

```bash
# Verify all pods are running
kubectl get pods -n yolov8

# Check services
kubectl get svc -n yolov8

# Check ingress and get application URL
kubectl get ingress -n yolov8

# Wait for DNS propagation (5-10 minutes)
source .env
watch -n 5 "dig ml.$DOMAIN_NAME +short"
```

**Check deployment status:**
```bash
# View pod logs
kubectl logs -n yolov8 -l app.kubernetes.io/component=backend -f

# Check certificate status (should show "Ready" after 2-5 minutes)
kubectl get certificate -n yolov8

# Test health endpoint (once DNS is propagated)
curl https://ml.$DOMAIN_NAME/health
```

### Step 6: Access Your Application

1. **Open your browser:** `https://ml.yourdomain.com`
2. **Upload a test image** with common objects (people, cars, animals)
3. **View detection results** with bounding boxes and labels

**Congratulations!** Your YOLOv8 MLOps application is now running on AWS EKS.

## Cleanup

To destroy all resources and stop charges:

```bash
# Delete Helm release
helm uninstall yolov8 -n yolov8
kubectl delete namespace yolov8

# Destroy infrastructure
cd infra
terraform destroy

# Optionally destroy bootstrap (if you won't use it again)
cd bootstrap
terraform destroy
```

**Important:** Always verify in the AWS Console that all resources are deleted to avoid unexpected charges.

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
2. Deploy application via ArgoCD for GitOps
3. Configure monitoring with Prometheus/Grafana
4. Implement custom domain logic
5. Add authentication
6. Scale for production load

## Cost Warning

This setup costs approximately **$265/month**. Remember to destroy resources when not in use!

## Support

- Check the main README.md for detailed documentation
- Review troubleshooting section
- Open GitHub issues for problems
