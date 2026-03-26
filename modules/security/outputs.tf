# modules/security/outputs.tf
# Values other modules need from security

output "alb_sg_id" {
  description = "Security group ID for ALB — allows 80/443 from internet"
  value       = aws_security_group.alb_sg.id
}

output "app_sg_id" {
  description = "Security group ID for EC2 and EKS — allows traffic from ALB only"
  value       = aws_security_group.app_sg.id
}

output "db_sg_id" {
  description = "Security group ID for DocumentDB — allows port 27017 from app only"
  value       = aws_security_group.db_sg.id
}

output "redis_sg_id" {
  description = "Security group ID for Redis — allows port 6379 from app only"
  value       = aws_security_group.redis_sg.id
}

output "msk_sg_id" {
  description = "Security group ID for MSK Kafka — allows ports 9092-9094 from app only"
  value       = aws_security_group.msk_sg.id
}

output "kms_key_arn" {
  description = "ARN of the KMS encryption key — used by DocDB, Redis, MSK, EBS, Secrets"
  value       = aws_kms_key.main.arn
}

output "waf_acl_arn" {
  description = "ARN of the WAF ACL — attach this to the ALB in the alb module"
  value       = aws_wafv2_web_acl.main.arn
}

output "docdb_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DocDB credentials"
  value       = aws_secretsmanager_secret.docdb_creds.arn
}

output "redis_secret_arn" {
  description = "ARN of the Secrets Manager secret holding Redis auth token"
  value       = aws_secretsmanager_secret.redis_creds.arn
}
