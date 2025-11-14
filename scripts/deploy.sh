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
NC='\033[0m'

echo "=================================="
echo "YOLOv8 MLOps Deployment"
echo "=================================="

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

    echo -e "${GREEN}✓ Application deployed${NC}"
}

# Verify deployment
verify_deployment() {
    echo -e "\n${YELLOW}Verifying deployment...${NC}"

    kubectl get pods -n yolov8
    kubectl get svc -n yolov8
    kubectl get ingress -n yolov8

    echo -e "\n${GREEN}Deployment complete!${NC}"
    echo -e "\nApplication URL: ${GREEN}https://ml.${DOMAIN_NAME}${NC}"
    echo -e "\nNote: DNS propagation may take 5-10 minutes."
}

# Main
main() {
    build_and_push
    deploy_helm
    verify_deployment
}

main
