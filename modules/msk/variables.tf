# modules/msk/variables.tf

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "data_subnet_ids" {
  type        = list(string)
  description = "Data subnet IDs — one per Kafka broker. Each broker in a different AZ."
}

variable "msk_sg_id" {
  type        = string
  description = "Security group that allows Kafka ports 9092-9094 from app only."
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting Kafka message storage."
}
