# modules/elasticache/variables.tf

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "data_subnet_ids" {
  type        = list(string)
  description = "Data subnet IDs. Redis lives here — isolated from internet."
}

variable "redis_sg_id" {
  type        = string
  description = "Security group that allows port 6379 from app only."
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting Redis data at rest."
}

variable "redis_auth_token" {
  type        = string
  description = "Password for Redis connections. Min 16 characters."
  sensitive   = true
}
