# Data source for Route53 zone
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Namespace for ingress controller
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = {
      name = "ingress-nginx"
    }
  }
}

# Namespace for cert-manager
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      name = "cert-manager"
    }
  }
}

# Namespace for external-dns
resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
    labels = {
      name = "external-dns"
    }
  }
}

# Namespace for ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }
}

# IAM Role for ExternalDNS (IRSA)
resource "aws_iam_role" "external_dns" {
  name = "${var.project_name}-${var.environment}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-dns:external-dns"
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for ExternalDNS
resource "aws_iam_policy" "external_dns" {
  name        = "${var.project_name}-${var.environment}-external-dns"
  description = "Policy for ExternalDNS to manage Route53 records"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Attach policy to ExternalDNS role
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# IAM Role for Cert-Manager (IRSA)
resource "aws_iam_role" "cert_manager" {
  name = "${var.project_name}-${var.environment}-cert-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for Cert-Manager
resource "aws_iam_policy" "cert_manager" {
  name        = "${var.project_name}-${var.environment}-cert-manager"
  description = "Policy for Cert-Manager to manage Route53 for DNS challenges"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange"
        ]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Attach policy to Cert-Manager role
resource "aws_iam_role_policy_attachment" "cert_manager" {
  role       = aws_iam_role.cert_manager.name
  policy_arn = aws_iam_policy.cert_manager.arn
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Helm Release: Nginx Ingress Controller
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.8.3"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                  = "tcp"
            "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
          }
        }
        metrics = {
          enabled = true
        }
        config = {
          use-forwarded-headers      = "true"
          compute-full-forwarded-for = "true"
        }
      }
    })
  ]
}

# Helm Release: ExternalDNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.14.0"
  namespace  = kubernetes_namespace.external_dns.metadata[0].name

  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
        }
      }
      provider      = "aws"
      policy        = "sync"
      sources       = ["ingress", "service"]
      domainFilters = [var.domain_name]
      txtOwnerId    = var.cluster_name
      aws = {
        region = var.aws_region
      }
    })
  ]

  depends_on = [aws_iam_role_policy_attachment.external_dns]
}

# Helm Release: Cert-Manager
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.13.2"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  values = [
    yamlencode({
      installCRDs = true
      serviceAccount = {
        create = true
        name   = "cert-manager"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager.arn
        }
      }
      global = {
        leaderElection = {
          namespace = "cert-manager"
        }
      }
      securityContext = {
        fsGroup = 1001
      }
    })
  ]

  depends_on = [aws_iam_role_policy_attachment.cert_manager]
}

# ClusterIssuer for Let's Encrypt (using DNS challenge with Route53)
resource "kubectl_manifest" "letsencrypt_production" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-production"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "admin@${var.domain_name}"
        privateKeySecretRef = {
          name = "letsencrypt-production"
        }
        solvers = [{
          dns01 = {
            route53 = {
              region = var.aws_region
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# Helm Release: ArgoCD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled     = true
          ingressClassName = "nginx"
          annotations = {
            "cert-manager.io/cluster-issuer"              = "letsencrypt-production"
            "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
          }
          hosts = ["argocd.${var.domain_name}"]
          tls = [
            {
              secretName = "argocd-tls"
              hosts      = ["argocd.${var.domain_name}"]
            }
          ]
        }
        extraArgs = [
          "--insecure" # ArgoCD server runs with TLS, ingress handles external TLS
        ]
      }
      configs = {
        params = {
          "server.insecure" = true # Let ingress handle TLS
        }
        cm = {
          "url" = "https://argocd.${var.domain_name}"
        }
      }
      controller = {
        metrics = {
          enabled = true
        }
      }
      repoServer = {
        metrics = {
          enabled = true
        }
      }
      applicationSet = {
        enabled = true
      }
    })
  ]

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.cert_manager,
    kubectl_manifest.letsencrypt_production
  ]
}