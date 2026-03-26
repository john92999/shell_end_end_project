# modules/ec2/variables.tf

variable "environment" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs. EC2 instances run here — not reachable from internet."
}

variable "app_sg_id" {
  type        = string
  description = "App security group — allows traffic from ALB on port 8080 only."
}

variable "ec2_instance_profile" {
  type        = string
  description = "IAM instance profile name. Gives EC2 permission to call Secrets Manager, ECR, SSM."
}

variable "api_target_group_arn" {
  type        = string
  description = "ALB target group ARN. ASG registers instances here so ALB can route to them."
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting EBS volumes (EC2 disks)."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance size. t3.small for dev, t3.large or m5.large for prod."
  default     = "t3.small"
}

variable "ecr_api_url" {
  type        = string
  description = "ECR URL for todo-api Docker image. (For future Docker-based deployment.)"
}

variable "docdb_endpoint" {
  type        = string
  description = "DocumentDB cluster endpoint. Passed to app as connection string."
}

variable "redis_endpoint" {
  type        = string
  description = "ElastiCache Redis endpoint. Passed to app for cache connection."
}

variable "msk_brokers" {
  type        = string
  description = "MSK Kafka bootstrap brokers string. Passed to app for Kafka connection."
}

variable "secrets_arn" {
  type        = string
  description = "ARN of Secrets Manager secret containing DB credentials."
}

variable "redis_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret holding the Redis auth token. Fetched at EC2 startup — never embedded in user_data."
}
