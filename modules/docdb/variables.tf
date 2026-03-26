# modules/docdb/variables.tf

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "data_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs from the data layer. DocumentDB lives here — most isolated."
}

variable "db_sg_id" {
  type        = string
  description = "Security group ID that only allows port 27017 from the app layer."
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt DocumentDB storage at rest."
}

variable "docdb_password" {
  type        = string
  description = "Master password for the DocumentDB cluster."
  sensitive   = true
}
