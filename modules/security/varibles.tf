# modules/security/variables.tf
# All inputs this module needs — these were MISSING in the original code,
# which is why Terraform complained about undeclared variables.

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID from the vpc module. Security Groups belong to a specific VPC."
}

variable "docdb_password" {
  type        = string
  description = "Master password for DocumentDB. Stored in Secrets Manager."
  sensitive   = true
}

variable "redis_auth_token" {
  type        = string
  description = "Authentication token for Redis. Stored in Secrets Manager."
  sensitive   = true
}

# alb_arn is needed AFTER the ALB is created to attach WAF to it.
# We use a default of "" here and the association only runs when
# this is provided (after ALB module runs).
variable "alb_arn" {
  type        = string
  description = "ARN of the ALB. WAF is attached to this after ALB is created."
  default     = ""
}
