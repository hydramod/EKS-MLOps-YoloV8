# Data sources
data "aws_caller_identity" "current" {}

# Local variables
locals {
  account_id = data.aws_caller_identity.current.account_id
  fqdn       = "${var.subdomain}.${var.domain_name}"

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

# ECR Module
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

# EKS Module
module "eks" {
  source = "./modules/eks"

  project_name             = var.project_name
  environment              = var.environment
  cluster_version          = var.cluster_version
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  node_group_instance_types = var.node_group_instance_types
  node_group_desired_size  = var.node_group_desired_size
  node_group_min_size      = var.node_group_min_size
  node_group_max_size      = var.node_group_max_size
  tags                     = local.common_tags
}

# Route53 Module
module "route53" {
  source = "./modules/route53"

  domain_name = var.domain_name
  subdomain   = var.subdomain
  tags        = local.common_tags

  # Will be updated after ingress creation
  create_record = false
}

# Helm Module - Install Nginx Ingress, ExternalDNS, Cert-Manager
module "helm" {
  source = "./modules/helm"

  project_name       = var.project_name
  environment        = var.environment
  cluster_name       = module.eks.cluster_name
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  domain_name        = var.domain_name
  subdomain          = var.subdomain
  aws_region         = var.aws_region
  tags               = local.common_tags

  depends_on = [module.eks]
}
