# ─────────────────────────────────────────────────────────────────
# variables.tf  (ROOT LEVEL)
#
# PURPOSE: Declares all input variables for the root module.
# Think of variables as "parameters" — they let you change values
# without editing the code itself.
#
# Actual values go in terraform.tfvars (never commit to git).
# ─────────────────────────────────────────────────────────────────

# The AWS region where everything will be created.
# ap-south-1 = Mumbai, India
variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
  default     = "ap-south-1"
}

# Environment name — used as a prefix in all resource names
# so you can tell dev resources from prod resources
variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}

# ── VPC / Networking ──────────────────────────────────────────────

variable "vpc_cidr" {
  type        = string
  description = "IP address range for the entire VPC. /16 gives 65,536 addresses."
  default     = "10.0.0.0/16"
}

variable "public_cidrs" {
  type        = list(string)
  description = "IP ranges for public subnets (one per AZ). ALB lives here."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_cidrs" {
  type        = list(string)
  description = "IP ranges for private subnets (one per AZ). EKS and EC2 live here."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "data_cidrs" {
  type        = list(string)
  description = "IP ranges for data subnets (one per AZ). DocumentDB, Redis, MSK live here."
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AZs. We use 2 for high availability (if one data centre fails, the other serves traffic)."
  default     = ["ap-south-1a", "ap-south-1b"]
}

# ── Database (DocumentDB = MongoDB on AWS) ────────────────────────

variable "docdb_password" {
  type        = string
  description = "Master password for DocumentDB. Set this in terraform.tfvars — never hardcode!"
  sensitive   = true # Terraform will not print this value in logs
  default = "admin@123"
}

# ── Cache (ElastiCache Redis) ─────────────────────────────────────

variable "redis_auth_token" {
  type        = string
  description = "Password for Redis. Min 16 characters. Set in terraform.tfvars."
  sensitive   = true
  default = "admin@123"
}

# ── Application ───────────────────────────────────────────────────

variable "api_instance_type" {
  type        = string
  description = "EC2 instance size for the todo-api. t3.small is good for dev."
  default     = "t3.small"
}

variable "eks_node_instance_type" {
  type        = string
  description = "EC2 instance size for Kubernetes worker nodes."
  default     = "t3.medium"
}
