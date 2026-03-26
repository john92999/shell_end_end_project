# modules/msk/outputs.tf

output "bootstrap_brokers" {
  description = "TLS broker endpoints. todo-api uses these to connect to Kafka."
  value       = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "cluster_arn" {
  description = "MSK cluster ARN — used for IAM policies and monitoring"
  value       = aws_msk_cluster.main.arn
}
