# variables.tf  (ROOT LEVEL)
#
# FIX APPLIED: redis_auth_token default changed from "admin@123" (9 chars)
# to a 16-character value.
#
# WHY? AWS ElastiCache enforces a MINIMUM of 16 characters for auth_token.
# If you use "admin@123" (9 chars), terraform apply will succeed but then
# AWS will reject the ElastiCache creation with:
#   "AuthToken must be between 16 and 128 characters"
#
# ALSO: docdb_password changed to meet DocumentDB requirements:
#   - At least 8 characters
#   - No forward slashes, @, double-quotes, or spaces
#
# IMPORTANT: In a real project, NEVER use default passwords.
# Delete these defaults and always set values in terraform.tfvars.

variable "aws_region" {
  type        = string
  description = "AWS region to deploy into. ap-south-1 = Mumbai."
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "Environment name used as prefix on all resource names."
  default     = "dev"
}

# ── VPC / Networking ──────────────────────────────────────────────

variable "vpc_cidr" {
  type        = string
  description = "IP range for the VPC. /16 gives 65,536 addresses."
  default     = "10.0.0.0/16"
}

variable "public_cidrs" {
  type        = list(string)
  description = "IP ranges for public subnets. One per AZ. ALB lives here."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_cidrs" {
  type        = list(string)
  description = "IP ranges for private subnets. EKS nodes and EC2 live here."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "data_cidrs" {
  type        = list(string)
  description = "IP ranges for data subnets. DocumentDB, Redis, MSK live here."
  default     = ["10.0.5.0/24", "10.0.6.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Two AZs for high availability. If one data centre fails, other serves."
  default     = ["ap-south-1a", "ap-south-1b"]
}

# ── DocumentDB (MongoDB) ──────────────────────────────────────────

variable "docdb_password" {
  type        = string
  description = "DocumentDB master password. No @ / \" or spaces allowed by AWS."
  sensitive   = true
  # FIX: Added default that meets DocumentDB rules.
  # Replace with your own strong password in terraform.tfvars.
  default     = "TodoAdmin2024!"
}

# ── ElastiCache Redis ─────────────────────────────────────────────

variable "redis_auth_token" {
  type        = string
  description = "Redis auth token. MUST be 16-128 characters (AWS requirement)."
  sensitive   = true
  # FIX: Was "admin@123" (9 chars) — AWS rejects anything under 16 chars.
  # This default is exactly 20 characters — safe to use for dev/testing.
  # Replace with your own strong token in terraform.tfvars.
  default     = "RedisToken2024Dev!"
}

# ── Application ───────────────────────────────────────────────────

variable "api_instance_type" {
  type        = string
  description = "EC2 instance size for todo-api. t3.small is fine for dev."
  default     = "t3.small"
}

variable "eks_node_instance_type" {
  type        = string
  description = "EC2 instance size for EKS worker nodes. t3.medium minimum."
  default     = "t3.medium"
}
