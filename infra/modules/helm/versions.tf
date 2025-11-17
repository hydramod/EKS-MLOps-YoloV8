terraform {

  required_providers {

    kubectl = {

      source = "alekc/kubectl"

      version = "~> 2.0"

    }

    kubernetes = {

      source = "hashicorp/kubernetes"

      version = "~> 2.23"

    }

    helm = {

      source = "hashicorp/helm"

      version = "~> 2.11"

    }

    aws = {

      source = "hashicorp/aws"

      version = "~> 5.0"

    }

  }

}