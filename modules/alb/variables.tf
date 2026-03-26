# modules/alb/variables.tf

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the ALB and target groups are created."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs. ALB must be here so browsers can reach it."
}

variable "alb_sg_id" {
  type        = string
  description = "Security group for ALB — allows 80/443 from internet."
}

variable "waf_acl_arn" {
  type        = string
  description = "WAF Web ACL ARN to attach to the ALB for attack protection."
}

variable "acm_certificate_arn" {
  type        = string
  description = "ARN of ACM SSL certificate for HTTPS. Get a free one from AWS Certificate Manager."
  default     = "" # set this to your real cert ARN, or remove HTTPS listener for dev
}
