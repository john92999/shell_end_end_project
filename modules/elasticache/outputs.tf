# modules/elasticache/outputs.tf
#
# PURPOSE: Exposes the Redis connection details so other modules
# (ec2 module) can pass them to the application as environment config.
#
# WHY THIS FILE WAS CAUSING THE ERROR:
#   main.tf line 152 said: module.elasticache.redis_endpoint
#   Terraform looked inside modules/elasticache/ for an output
#   named "redis_endpoint" — the file didn't exist, so it failed.
#   Creating this file with the correct output name fixes the error.

output "redis_endpoint" {
  # primary_endpoint_address = the write endpoint of the Redis primary node.
  # Your app connects here to both read and write cache data.
  # Format: <cluster-id>.xxxxx.ng.0001.apse1.cache.amazonaws.com
  description = "Redis primary endpoint. todo-api connects here to cache and read data."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port number. Always 6379 for standard Redis."
  value       = 6379
}

output "redis_reader_endpoint" {
  # reader_endpoint_address = a load-balanced endpoint across all replica nodes.
  # Use this for read-only operations to distribute load across replicas.
  description = "Redis reader endpoint. Use for read-heavy operations."
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
}
