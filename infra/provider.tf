terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }

  # Backend configuration for S3 state storage
  # IMPORTANT: Before uncommenting, you must first deploy the bootstrap infrastructure
  # See infra/bootstrap/README.md for instructions
  # Run: cd infra/bootstrap && terraform init && terraform apply
  # Then update the values below with the outputs from bootstrap

  backend "s3" {
    bucket         = "yolov8-mlops-terraform-state"  # From bootstrap output: state_bucket_name
    key            = "eks-mlops/terraform.tfstate"
    region         = "us-east-1"                     # Match your bootstrap region
    encrypt        = true
    dynamodb_table = "yolov8-mlops-terraform-lock"   # From bootstrap output: dynamodb_table_name
  }

  # Alternative: Comment out the backend above to use local state during initial testing
  # backend "local" {
  #   path = "terraform.tfstate"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "YOLOv8-MLOps"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.aws_region
      ]
    }
  }
}

# Kubectl provider configuration
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}
