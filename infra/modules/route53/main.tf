# Data source to get existing hosted zone
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Route53 record for the application (points to load balancer)
# This will be created after the ingress controller creates the load balancer
# You can also manage this via ExternalDNS automatically
resource "aws_route53_record" "app" {
  count = var.create_record ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}

# Note: In production, you would typically use ExternalDNS to automatically
# create and manage DNS records based on Kubernetes Ingress resources
# This is a manual fallback option
