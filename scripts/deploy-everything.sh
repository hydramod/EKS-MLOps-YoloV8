#!/bin/bash
# YOLOv8 MLOps - Intelligent End-to-End Deployment
# Safe to run multiple times - skips completed steps

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      YOLOv8 MLOps - Intelligent End-to-End Deployment        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"

START_TIME=$(date +%s)

# Check prerequisites
check_prerequisites() {
    log_step "STEP 1: Checking Prerequisites"
    local missing=0
    
    command -v aws &> /dev/null || { log_error "AWS CLI not found"; missing=1; }
    command -v terraform &> /dev/null || { log_error "Terraform not found"; missing=1; }
    command -v kubectl &> /dev/null || { log_error "kubectl not found"; missing=1; }
    command -v helm &> /dev/null || { log_error "Helm not found"; missing=1; }
    command -v docker &> /dev/null || { log_error "Docker not found"; missing=1; }
    
    if [ $missing -eq 1 ]; then exit 1; fi
    
    aws sts get-caller-identity &> /dev/null || { log_error "AWS credentials not configured"; exit 1; }
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_success "All prerequisites met (AWS Account: $AWS_ACCOUNT_ID)"
}

# Setup configuration
setup_configuration() {
    log_step "STEP 2: Configuration Setup"
    
    if [ -f .env ]; then
        log_success "Found existing configuration"
        source .env
        echo "  • Domain: $DOMAIN_NAME"
        echo "  • Region: $AWS_REGION"
        echo "  • Project: $PROJECT_NAME"
        read -p "Use existing? (y/n): " USE_EXISTING
        [ "$USE_EXISTING" != "y" ] && rm .env && get_config
    else
        get_config
    fi
    
    source .env
    [ -f infra/terraform.tfvars ] || create_tfvars
}

get_config() {
    read -p "Domain (e.g., alistechlab.click): " DOMAIN_NAME
    read -p "AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    read -p "Project name [yolov8-mlops]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-yolov8-mlops}
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    cat > .env <<EOF
DOMAIN_NAME=$DOMAIN_NAME
AWS_REGION=$AWS_REGION
PROJECT_NAME=$PROJECT_NAME
ACCOUNT_ID=$AWS_ACCOUNT_ID
EOF
    log_success "Configuration saved"
}

create_tfvars() {
    cat > infra/terraform.tfvars <<EOF
aws_region  = "$AWS_REGION"
environment = "production"
project_name = "$PROJECT_NAME"
vpc_cidr = "10.0.0.0/16"
availability_zones = ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]
cluster_version = "1.28"
node_group_instance_types = ["t3.medium"]
node_group_desired_size = 2
node_group_min_size = 1
node_group_max_size = 4
domain_name = "$DOMAIN_NAME"
subdomain = "ml"
backend_image_tag = "latest"
frontend_image_tag = "latest"
EOF
    log_success "Created terraform.tfvars"
}

# Bootstrap backend
bootstrap_backend() {
    log_step "STEP 3: Bootstrap State Backend"
    
    EXISTING_BUCKET=$(aws s3 ls | grep "${PROJECT_NAME}-tf-state" | awk '{print $3}' | head -1)
    
    if [ -n "$EXISTING_BUCKET" ]; then
        log_success "Backend exists: $EXISTING_BUCKET"
        STATE_BUCKET=$EXISTING_BUCKET
        DYNAMODB_TABLE="${PROJECT_NAME}-tf-lock"
    else
        log_info "Creating state backend..."
        RANDOM_SUFFIX=$(openssl rand -hex 4)
        STATE_BUCKET="${PROJECT_NAME}-tf-state-${RANDOM_SUFFIX}"
        DYNAMODB_TABLE="${PROJECT_NAME}-tf-lock"
        
        cat > infra/bootstrap/terraform.tfvars <<EOF
aws_region = "$AWS_REGION"
project_name = "$PROJECT_NAME"
state_bucket_name = "$STATE_BUCKET"
dynamodb_table_name = "$DYNAMODB_TABLE"
enable_point_in_time_recovery = true
state_retention_days = 90
EOF
        
        cd infra/bootstrap
        terraform init -input=false
        terraform apply -auto-approve
        cd ../..
        log_success "Backend created"
    fi
}

# Configure backend in provider.tf
configure_backend() {
    log_step "STEP 4: Configure Backend"
    
    if grep -q "bucket.*=.*\"$STATE_BUCKET\"" infra/provider.tf 2>/dev/null; then
        log_success "Backend already configured"
    else
        log_info "Updating provider.tf..."
        cd infra
        [ ! -f provider.tf.backup ] && cp provider.tf provider.tf.backup
        sed -i.tmp -e "s|bucket.*=.*\".*\"|bucket         = \"$STATE_BUCKET\"|" \
                   -e "s|dynamodb_table.*=.*\".*\"|dynamodb_table = \"$DYNAMODB_TABLE\"|" provider.tf
        rm -f provider.tf.tmp
        cd ..
        log_success "Backend configured"
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    log_step "STEP 5: Deploy Infrastructure"
    
    cd infra
    
    if aws eks describe-cluster --name "${PROJECT_NAME}-production-eks" --region "$AWS_REGION" &> /dev/null; then
        log_success "EKS cluster exists"
        terraform init -migrate-state -input=false 2>/dev/null || terraform init -reconfigure -input=false
        
        if terraform plan -var="domain_name=$DOMAIN_NAME" -detailed-exitcode &> /dev/null; then
            log_success "Infrastructure up to date"
        else
            log_warning "Updates available"
            read -p "Apply updates? (yes/no): " APPLY
            [ "$APPLY" == "yes" ] && terraform apply -var="domain_name=$DOMAIN_NAME" -auto-approve
        fi
    else
        log_info "Deploying infrastructure (15-20 minutes)..."
        # Try migrate first, fall back to reconfigure
        terraform init -migrate-state -input=false 2>/dev/null || terraform init -reconfigure -input=false
        terraform plan -var="domain_name=$DOMAIN_NAME" -out=tfplan
        
        log_warning "This creates VPC, EKS, ECR, Route53, etc."
        log_warning "Cost: ~\$265/month | Time: 15-20 minutes"
        read -p "Continue? (yes/no): " CONFIRM
        [ "$CONFIRM" != "yes" ] && { log_error "Cancelled"; exit 0; }
        
        terraform apply tfplan
        log_success "Infrastructure deployed"
    fi
    
    cd ..
}

# Deploy application
deploy_application() {
    log_step "STEP 6: Deploy Application"
    
    log_info "Configuring kubectl..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name "${PROJECT_NAME}-production-eks"
    kubectl cluster-info &> /dev/null || { log_error "Cannot connect to cluster"; exit 1; }
    
    log_info "Waiting for nodes..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s &> /dev/null
    log_success "Cluster ready"
    
    if helm list -n yolov8 | grep -q "yolov8"; then
        log_success "App already deployed"
        read -p "Redeploy? (y/n): " REDEPLOY
        [ "$REDEPLOY" != "y" ] && return
    fi
    
    log_info "Building images..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    cd app/backend
    docker build -t yolov8-backend -q .
    docker tag yolov8-backend:latest "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest"
    docker push "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest" > /dev/null
    log_success "Backend image pushed"
    
    cd ../frontend
    docker build -t yolov8-frontend -q .
    docker tag yolov8-frontend:latest "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest"
    docker push "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest" > /dev/null
    log_success "Frontend image pushed"
    
    cd ../..
    
    log_info "Deploying with Helm..."
    helm upgrade --install yolov8 ./charts/yolov8 \
        --namespace yolov8 \
        --create-namespace \
        --set global.domain="$DOMAIN_NAME" \
        --set global.subdomain=ml \
        --set backend.image.repository="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend" \
        --set backend.image.tag=latest \
        --set backend.image.pullPolicy=Always \
        --set frontend.image.repository="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend" \
        --set frontend.image.tag=latest \
        --set frontend.image.pullPolicy=Always \
        --wait --timeout 10m
    
    log_success "Application deployed"
}

# Deploy with ArgoCD (Optional GitOps)
deploy_with_argocd() {
    log_step "STEP 7: Deploy via ArgoCD (Optional GitOps)"

    # Check if ArgoCD is deployed
    if ! kubectl get namespace argocd &> /dev/null; then
        log_warning "ArgoCD namespace not found. Skipping ArgoCD deployment."
        log_info "ArgoCD should be automatically deployed by Terraform."
        return
    fi

    log_info "ArgoCD is available for GitOps-based deployment"
    echo -e "${CYAN}Benefits of ArgoCD:${NC}"
    echo -e "  • Automatic sync from Git repository"
    echo -e "  • Visual deployment status and history"
    echo -e "  • Easy rollback to previous versions"
    echo -e "  • Declarative GitOps workflow"

    read -p "Deploy with ArgoCD? (y/n): " USE_ARGOCD

    if [ "$USE_ARGOCD" != "y" ]; then
        log_info "Skipping ArgoCD deployment"
        return
    fi

    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD server..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server -n argocd &> /dev/null || {
        log_warning "ArgoCD server not ready yet. You can deploy via ArgoCD later."
        return
    }

    log_success "ArgoCD is ready"

    # Create ArgoCD application manifest with correct values
    log_info "Creating ArgoCD application..."

    cat > /tmp/yolov8-argocd-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yolov8
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/hydramod/EKS-MLOps-YoloV8.git
    targetRevision: main
    path: charts/yolov8
    helm:
      values: |
        global:
          domain: ${DOMAIN_NAME}
          subdomain: ml
        backend:
          image:
            repository: ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend
            tag: latest
            pullPolicy: Always
        frontend:
          image:
            repository: ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend
            tag: latest
            pullPolicy: Always
  destination:
    server: https://kubernetes.default.svc
    namespace: yolov8
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
EOF

    # Apply the ArgoCD application
    kubectl apply -f /tmp/yolov8-argocd-app.yaml

    # Get ArgoCD credentials
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A")

    log_success "ArgoCD application created"

    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ArgoCD GitOps Deployment Configured               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${CYAN}ArgoCD Details:${NC}"
    echo -e "  • URL:      ${GREEN}https://argocd.${DOMAIN_NAME}${NC}"
    echo -e "  • Username: ${YELLOW}admin${NC}"
    echo -e "  • Password: ${YELLOW}${ARGOCD_PASSWORD}${NC}"

    echo -e "\n${CYAN}Monitor Deployment:${NC}"
    echo -e "  kubectl get application yolov8 -n argocd"
    echo -e "  kubectl describe application yolov8 -n argocd"

    echo -e "\n${CYAN}Access ArgoCD UI:${NC}"
    echo -e "  1. Visit: https://argocd.${DOMAIN_NAME}"
    echo -e "  2. Login with credentials above"
    echo -e "  3. View 'yolov8' application status"

    # Clean up temp file
    rm -f /tmp/yolov8-argocd-app.yaml

    # Wait a moment for sync to start
    sleep 3

    # Show sync status
    log_info "Initial sync status:"
    kubectl get application yolov8 -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null && echo

}

# Verify
verify_deployment() {
    log_step "STEP 8: Verify Deployment"
    kubectl get pods,svc,ingress,certificate -n yolov8
}

# Summary
show_summary() {
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          🎉 Deployment Complete! 🎉                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${CYAN}Summary:${NC}"
    echo -e "  • Time: ${MINUTES}m ${SECONDS}s"
    echo -e "  • URL: ${GREEN}https://ml.${DOMAIN_NAME}${NC}"
    echo -e "\n${YELLOW}⏱️  Wait 5-10 min for DNS + SSL${NC}"
    echo -e "\n${CYAN}Test:${NC}"
    echo -e "  curl https://ml.${DOMAIN_NAME}/health"
    echo -e "\n${BLUE}💡 Run this script again to update!${NC}\n"
}

# Main
main() {
    check_prerequisites
    setup_configuration
    bootstrap_backend
    configure_backend
    deploy_infrastructure
    deploy_application
    deploy_with_argocd
    verify_deployment
    show_summary
}

main