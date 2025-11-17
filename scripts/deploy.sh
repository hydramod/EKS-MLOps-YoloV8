#!/bin/bash

# YOLOv8 MLOps Deployment Script
# Builds and deploys the application

set -e

# Load environment
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found. Run setup.sh first."
    exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================="
echo "YOLOv8 MLOps Deployment"
echo "=================================="

# Configure kubectl
configure_kubectl() {
    echo -e "\n${YELLOW}Configuring kubectl...${NC}"
    
    # Update kubeconfig for the EKS cluster
    aws eks update-kubeconfig --region $AWS_REGION --name ${PROJECT_NAME}-production-eks
    
    # Verify cluster is accessible
    if kubectl cluster-info &>/dev/null; then
        echo -e "${GREEN}✓ kubectl configured successfully${NC}"
        echo -e "${GREEN}✓ Connected to cluster: ${PROJECT_NAME}-production-eks${NC}"
    else
        echo -e "${RED}✗ Failed to connect to Kubernetes cluster${NC}"
        echo -e "${RED}Make sure the EKS cluster exists (run terraform apply first)${NC}"
        exit 1
    fi
    
    # Wait for nodes to be ready
    echo -e "${YELLOW}Waiting for nodes to be ready...${NC}"
    kubectl wait --for=condition=Ready nodes --all --timeout=300s || {
        echo -e "${RED}✗ Nodes are not ready${NC}"
        kubectl get nodes
        exit 1
    }
    
    echo -e "${GREEN}✓ Cluster nodes are ready${NC}"
}

# Build and push images
build_and_push() {
    echo -e "\n${YELLOW}Building and pushing Docker images...${NC}"

    # Login to ECR
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin \
        ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

    # Build backend
    echo -e "\n${YELLOW}Building backend...${NC}"
    cd app/backend
    docker build -t yolov8-backend .
    docker tag yolov8-backend:latest \
        ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest
    docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend:latest

    echo -e "${GREEN}✓ Backend image pushed${NC}"

    # Build frontend
    echo -e "\n${YELLOW}Building frontend...${NC}"
    cd ../frontend
    docker build -t yolov8-frontend .
    docker tag yolov8-frontend:latest \
        ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest
    docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend:latest

    echo -e "${GREEN}✓ Frontend image pushed${NC}"

    cd ../..
}

# Deploy with Helm
deploy_helm() {
    echo -e "\n${YELLOW}Deploying with Helm...${NC}"

    # Deploy with Helm - let Helm create the namespace with proper labels
    helm upgrade --install yolov8 ./charts/yolov8 \
        --namespace yolov8 \
        --create-namespace \
        --set global.domain=$DOMAIN_NAME \
        --set global.subdomain=ml \
        --set backend.image.repository=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-backend \
        --set backend.image.tag=latest \
        --set backend.image.pullPolicy=Always \
        --set frontend.image.repository=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-production-frontend \
        --set frontend.image.tag=latest \
        --set frontend.image.pullPolicy=Always \
        --wait \
        --timeout 10m

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Application deployed${NC}"
    else
        echo -e "${RED}✗ Deployment failed${NC}"
        echo -e "${YELLOW}Checking pod status...${NC}"
        kubectl get pods -n yolov8
        echo -e "${YELLOW}Recent events:${NC}"
        kubectl get events -n yolov8 --sort-by='.lastTimestamp' | tail -20
        exit 1
    fi
}

# Verify deployment
verify_deployment() {
    echo -e "\n${YELLOW}Verifying deployment...${NC}"

    echo -e "\n${YELLOW}Pods:${NC}"
    kubectl get pods -n yolov8
    
    echo -e "\n${YELLOW}Services:${NC}"
    kubectl get svc -n yolov8
    
    echo -e "\n${YELLOW}Ingress:${NC}"
    kubectl get ingress -n yolov8

    # Get the application URL
    INGRESS_HOST=$(kubectl get ingress -n yolov8 -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "ml.${DOMAIN_NAME}")
    LB_HOSTNAME=$(kubectl get ingress -n yolov8 -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")

    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  Deployment Complete! 🚀                       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${GREEN}Application URL:${NC} https://${INGRESS_HOST}"
    echo -e "${YELLOW}Load Balancer:${NC} ${LB_HOSTNAME}"
    echo -e "\n${YELLOW}⏱️  DNS Propagation:${NC} 5-10 minutes (ExternalDNS is working)"
    echo -e "${YELLOW}🔒 SSL Certificate:${NC} 2-5 minutes (Cert-Manager is working)"
    echo -e "\n${GREEN}Tip:${NC} Monitor pods with: ${YELLOW}kubectl get pods -n yolov8 -w${NC}"
}

# Main
main() {
    configure_kubectl
    build_and_push
    deploy_helm
    verify_deployment
}

main