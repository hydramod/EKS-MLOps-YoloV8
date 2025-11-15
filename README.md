# YOLOv8 MLOps on AWS EKS

A production-ready MLOps implementation for deploying YOLOv8 object detection as a scalable web application on AWS EKS with complete CI/CD automation.

## Overview

This project demonstrates a complete MLOps workflow for deploying a machine learning application using:
- **YOLOv8** for real-time object detection
- **AWS EKS** for Kubernetes orchestration
- **Terraform** for Infrastructure as Code
- **Helm** for application deployment
- **GitHub Actions** for CI/CD automation
- **HTTPS** with automated TLS certificates

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Browser                             │
└──────────────────────┬──────────────────────────────────────────┘
                       │ HTTPS (TLS)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Route 53 (DNS)                              │
│                   ml.yourdomain.com                              │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Network Load Balancer                           │
│              (Created by Ingress Controller)                     │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                       AWS EKS Cluster                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Nginx Ingress Controller                     │  │
│  └────────────┬──────────────────────────────────────────────┘  │
│               │                                                  │
│       ┌───────┴───────┐                                          │
│       ▼               ▼                                          │
│  ┌─────────┐    ┌──────────┐                                    │
│  │Frontend │    │ Backend  │                                    │
│  │Service  │    │ Service  │                                    │
│  │(React)  │    │(Flask +  │                                    │
│  │         │    │ YOLOv8)  │                                    │
│  └────┬────┘    └────┬─────┘                                    │
│       │              │                                           │
│  ┌────▼────┐    ┌────▼─────┐                                    │
│  │Frontend │    │Backend   │                                    │
│  │Pods (2) │    │Pods (2)  │                                    │
│  └─────────┘    └──────────┘                                    │
│                                                                  │
│  Supporting Services:                                            │
│  • ExternalDNS (manages Route53 records)                        │
│  • Cert-Manager (manages TLS certificates)                      │
│  • Horizontal Pod Autoscaler (scales based on load)             │
└──────────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **User uploads image** → Frontend (React UI)
2. **Frontend sends POST request** → `/predict` endpoint
3. **Backend receives image** → Flask API
4. **YOLOv8 processes image** → Object detection
5. **Results returned to frontend** → JSON with bounding boxes
6. **Frontend displays results** → Visual overlay on image

## Project Structure

```
.
├── app/
│   ├── backend/              # Flask API with YOLOv8
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   ├── requirements.txt
│   │   └── models/
│   └── frontend/             # React UI
│       ├── Dockerfile
│       ├── index.html
│       ├── app.js
│       ├── styles.css
│       └── server.js
├── infra/                    # Terraform Infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── modules/
│       ├── vpc/              # VPC, Subnets, NAT
│       ├── eks/              # EKS Cluster, Node Groups
│       ├── ecr/              # Container Registries
│       ├── route53/          # DNS Management
│       └── helm/             # Nginx, ExternalDNS, Cert-Manager (Let's Encrypt)
├── charts/
│   └── yolov8/               # Helm Chart for Application
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── backend-deployment.yaml
│           ├── frontend-deployment.yaml
│           ├── ingress.yaml
│           └── ...
└── .github/
    └── workflows/            # CI/CD Pipelines
        ├── build-and-push.yml
        ├── terraform.yml
        └── deploy-app.yml
```

## Prerequisites

### Required Tools
- **AWS CLI** (v2.x)
- **Terraform** (>= 1.5.0)
- **kubectl** (>= 1.28)
- **Helm** (>= 3.13)
- **Docker** (for local testing)
- **Git**

### AWS Requirements
- AWS Account with appropriate permissions
- Route 53 hosted zone for your domain
- AWS credentials configured

### GitHub Requirements
- GitHub repository
- GitHub Actions enabled
- Required secrets configured (see below)

## Getting Started

### Step 0: Bootstrap State Backend (FIRST TIME ONLY)

Before deploying any infrastructure, you must create the Terraform state backend. This is a one-time setup.

**Option 1: Automated Bootstrap (Recommended)**
```bash
./scripts/bootstrap.sh
```

**Option 2: Manual Bootstrap**
```bash
cd infra/bootstrap
terraform init
terraform apply
```

This creates:
- S3 bucket for Terraform state storage
- DynamoDB table for state locking
- IAM policy for state access

See `infra/bootstrap/README.md` for detailed instructions.

### Step 1: Configure AWS and Domain

1. **Create Route 53 Hosted Zone**
   ```bash
   aws route53 create-hosted-zone --name yourdomain.com --caller-reference $(date +%s)
   ```

2. **Update domain nameservers** with your registrar using Route 53 NS records

### Step 2: Configure Terraform Variables

1. **Update `infra/variables.tf`** with your values:
   ```hcl
   variable "domain_name" {
     default = "yourdomain.com"  # Change this
   }

   variable "aws_region" {
     default = "us-east-1"       # Change if needed
   }
   ```

2. **Update `infra/provider.tf`** backend configuration:
   ```hcl
   backend "s3" {
     bucket = "yolov8-terraform-state"  # Your bucket name
     key    = "eks-mlops/terraform.tfstate"
     region = "us-east-1"
   }
   ```

### Step 3: Deploy Infrastructure

1. **Initialize Terraform**
   ```bash
   cd infra
   terraform init
   ```

2. **Review the plan**
   ```bash
   terraform plan
   ```

3. **Apply the infrastructure**
   ```bash
   terraform apply
   ```

   This will create:
   - VPC with public/private subnets across 3 AZs
   - EKS cluster with managed node group
   - ECR repositories for backend and frontend
   - Nginx Ingress Controller
   - ExternalDNS for Route 53 automation
   - Cert-Manager for automated TLS certificate management with Let's Encrypt

   **Note:** This process takes approximately 15-20 minutes.

4. **Configure kubectl**
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name yolov8-mlops-production-eks
   ```

5. **Verify cluster**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

### Step 4: Build and Push Docker Images

1. **Login to ECR**
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
   ```

2. **Build backend image**
   ```bash
   cd app/backend
   docker build -t yolov8-backend .
   docker tag yolov8-backend:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/yolov8-mlops-production-backend:latest
   docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/yolov8-mlops-production-backend:latest
   ```

3. **Build frontend image**
   ```bash
   cd app/frontend
   docker build -t yolov8-frontend .
   docker tag yolov8-frontend:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/yolov8-mlops-production-frontend:latest
   docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/yolov8-mlops-production-frontend:latest
   ```

### Step 5: Deploy Application with Helm

1. **Update Helm values**

   Edit `charts/yolov8/values.yaml`:
   ```yaml
   global:
     domain: yourdomain.com
     subdomain: ml

   backend:
     image:
       repository: <account-id>.dkr.ecr.us-east-1.amazonaws.com/yolov8-mlops-production-backend
       tag: latest

   frontend:
     image:
       repository: <account-id>.dkr.ecr.us-east-1.amazonaws.com/yolov8-mlops-production-frontend
       tag: latest
   ```

2. **Deploy with Helm**
   ```bash
   helm upgrade --install yolov8 ./charts/yolov8 \
     --namespace yolov8 \
     --create-namespace \
     --wait \
     --timeout 10m
   ```

3. **Verify deployment**
   ```bash
   kubectl get pods -n yolov8
   kubectl get svc -n yolov8
   kubectl get ingress -n yolov8
   ```

4. **Wait for DNS propagation** (5-10 minutes)
   ```bash
   watch -n 5 "dig ml.yourdomain.com +short"
   ```

5. **Access your application**

   Open your browser to: `https://ml.yourdomain.com`

## CI/CD with GitHub Actions

### Setup GitHub Secrets

Configure the following secrets in your GitHub repository (Settings > Secrets and variables > Actions):

1. **AWS_ROLE_TO_ASSUME** - IAM role ARN for OIDC authentication
2. **DOMAIN_NAME** - Your domain (e.g., `yourdomain.com`)

### Configure AWS OIDC for GitHub Actions

1. **Create OIDC provider**
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create IAM role** with trust policy:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {
         "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
       },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": {
           "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
           "token.actions.githubusercontent.com:sub": "repo:<username>/<repo>:ref:refs/heads/main"
         }
       }
     }]
   }
   ```

3. **Attach policies** to the role:
   - AdministratorAccess (or create a more restrictive custom policy)

### Automated Workflows

The project includes 4 GitHub Actions workflows:

1. **build-and-push.yml** - Builds and pushes Docker images to ECR
2. **terraform.yml** - Plans and applies Terraform changes
3. **deploy-app.yml** - Deploys application with Helm
4. **destroy.yml** - Destroys all infrastructure (manual trigger)

### Triggering Deployments

**Automatic deployment:**
```bash
git add .
git commit -m "Update application"
git push origin main
```

**Manual deployment:**
- Go to Actions tab in GitHub
- Select "Deploy Application" workflow
- Click "Run workflow"
- Specify image tags (or use `latest`)

## Testing the Application

### Local Testing (Before Deployment)

1. **Backend**
   ```bash
   cd app/backend
   docker build -t yolov8-backend .
   docker run -p 5000:5000 yolov8-backend

   # Test health endpoint
   curl http://localhost:5000/health

   # Test prediction
   curl -X POST -F "image=@test.jpg" http://localhost:5000/predict
   ```

2. **Frontend**
   ```bash
   cd app/frontend
   docker build -t yolov8-frontend .
   docker run -p 3000:3000 yolov8-frontend

   # Open browser
   open http://localhost:3000
   ```

### Production Testing

1. **Health check**
   ```bash
   curl https://ml.yourdomain.com/health
   ```

2. **Upload test image**
   - Visit `https://ml.yourdomain.com`
   - Click upload area
   - Select an image with common objects (people, cars, animals)
   - View detection results with bounding boxes

### Monitoring

1. **Check pod logs**
   ```bash
   # Backend logs
   kubectl logs -n yolov8 -l app.kubernetes.io/component=backend -f

   # Frontend logs
   kubectl logs -n yolov8 -l app.kubernetes.io/component=frontend -f
   ```

2. **Check ingress**
   ```bash
   kubectl describe ingress -n yolov8
   ```

3. **Check HPA status**
   ```bash
   kubectl get hpa -n yolov8
   ```

## Cost Estimation

Approximate monthly costs for running in `us-east-1`:

| Resource | Specification | Monthly Cost |
|----------|--------------|--------------|
| EKS Cluster | Control plane | $73 |
| EC2 Instances | 2x t3.medium nodes | $60 |
| NAT Gateway | 3 AZs | $100 |
| Network Load Balancer | 1 NLB | $20 |
| Route 53 | Hosted zone + queries | $1 |
| ECR | Storage (< 10 GB) | $1 |
| Data Transfer | Moderate usage | $10 |
| **Total** | | **~$265/month** |

### Cost Optimization Tips

1. **Use Fargate** instead of EC2 nodes for variable workloads
2. **Single NAT Gateway** for dev/test environments
3. **Spot instances** for node groups (60-90% savings)
4. **Auto-scaling** to scale down during off-hours
5. **Delete when not in use** (use destroy workflow)

## Cleanup

### Destroy All Resources

**Option 1: GitHub Actions**
1. Go to Actions > Destroy Infrastructure
2. Click "Run workflow"
3. Type `destroy` to confirm

**Option 2: Manual**
```bash
# Delete Helm release
helm uninstall yolov8 -n yolov8

# Delete namespace
kubectl delete namespace yolov8

# Destroy Terraform infrastructure
cd infra
terraform destroy
```

**Note:** Always verify all resources are deleted in AWS Console to avoid unexpected charges.

## Troubleshooting

### Common Issues

**1. Pods not starting**
```bash
kubectl describe pod <pod-name> -n yolov8
kubectl logs <pod-name> -n yolov8
```

**2. Ingress not getting external IP**
```bash
kubectl get svc -n ingress-nginx
# Wait 5-10 minutes for load balancer provisioning
```

**3. Certificate not issued**
```bash
kubectl get certificate -n yolov8
kubectl describe certificate yolov8-tls -n yolov8
kubectl logs -n cert-manager -l app=cert-manager
```

**4. DNS not resolving**
```bash
# Check ExternalDNS logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Verify Route53 record
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

**5. Image pull errors**
```bash
# Verify ECR permissions
aws ecr describe-repositories
aws ecr get-login-password --region us-east-1
```

## Security Best Practices

- ✅ Non-root containers
- ✅ Network policies (can be added)
- ✅ IRSA for pod permissions
- ✅ Encrypted ECR repositories
- ✅ Private subnets for nodes
- ✅ TLS/HTTPS enforced
- ✅ Security group restrictions
- ✅ Image scanning enabled

## Performance Tuning

### Backend Optimization
- Adjust `resources.limits` in `values.yaml`
- Increase replica count for high load
- Configure HPA thresholds
- Use GPU instances for faster inference (g4dn family)

### Frontend Optimization
- Enable CDN (CloudFront)
- Compress assets
- Implement caching headers

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - See LICENSE file

## Support

For issues and questions:
- Open a GitHub issue
- Check troubleshooting section
- Review AWS EKS documentation

## Acknowledgments

- YOLOv8 by Ultralytics
- Terraform AWS modules
- Kubernetes community
- AWS EKS best practices

---

**Built with ❤️ for MLOps learning and production deployments**
