output "alb_dns_name" {
  description = "Paste this into your browser to open the app"
  value       = module.alb.alb_dns_name
}

output "eks_cluster_name" {
  description = "Run: aws eks update-kubeconfig --name <this_value> --region ap-south-1"
  value       = module.eks.cluster_name
}

output "ecr_api_url" {
  description = "Use this URL when building and pushing the todo-api Docker image"
  value       = module.ecr.todo_api_url
}

output "ecr_ui_url" {
  description = "Use this URL when building and pushing the todo-ui Docker image"
  value       = module.ecr.todo_ui_url
}

output "docdb_endpoint" {
  description = "DocumentDB (MongoDB) connection endpoint for todo-api"
  value       = module.docdb.cluster_endpoint
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint for todo-api"
  value       = module.elasticache.redis_endpoint
}

output "msk_brokers" {
  description = "MSK Kafka bootstrap brokers for todo-api"
  value       = module.msk.bootstrap_brokers
}
