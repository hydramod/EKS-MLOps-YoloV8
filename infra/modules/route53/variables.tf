variable "domain_name" {
  description = "Domain name"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for the application"
  type        = string
}

variable "create_record" {
  description = "Whether to create the Route53 record"
  type        = bool
  default     = false
}

variable "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  type        = string
  default     = ""
}

variable "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
