# Subnet group
resource "aws_elasticache_subnet_group""main" {
  name       = "${var.env}-redis-subnet-group"
  subnet_ids = var.data_subnet_ids
}

# Redis Replication Group — cluster mode, 2 nodes across 2 AZs
resource "aws_elasticache_replication_group""redis" {
  replication_group_id       = "${var.env}-redis"
  description                = "Redis cache for todo app"
  engine                     = "redis"
  engine_version             = "7.0"
  node_type                  = "cache.t3.micro"
  num_cache_clusters         = 2     # primary + replica for HA
  automatic_failover_enabled = true  # auto-promote replica if primary fails
  multi_az_enabled           = true
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [var.redis_sg_id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token
  tags = { Name = "${var.env}-redis" }
}
