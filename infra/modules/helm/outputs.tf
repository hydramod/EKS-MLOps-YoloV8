output "nginx_ingress_namespace" {
  description = "Namespace where Nginx Ingress is deployed"
  value       = kubernetes_namespace.ingress_nginx.metadata[0].name
}

output "cert_manager_namespace" {
  description = "Namespace where Cert-Manager is deployed"
  value       = kubernetes_namespace.cert_manager.metadata[0].name
}

output "external_dns_namespace" {
  description = "Namespace where ExternalDNS is deployed"
  value       = kubernetes_namespace.external_dns.metadata[0].name
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS"
  value       = aws_iam_role.external_dns.arn
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for Cert-Manager"
  value       = aws_iam_role.cert_manager.arn
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_url" {
  description = "ArgoCD server URL"
  value       = "https://argocd.${var.domain_name}"
}