variable "domain_name" {
  description = "Domain name for the certificate"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for the certificate"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
