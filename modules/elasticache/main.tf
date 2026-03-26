# ─────────────────────────────────────────────────────────────────
# modules/elasticache/main.tf
#
# PURPOSE: Creates ElastiCache Redis — an in-memory cache.
#
# WHAT IS REDIS?
#   Redis is a database that stores data in RAM (memory) instead
#   of on disk. This makes it 100x faster than DocumentDB.
#
# WHY DO WE NEED REDIS IF WE HAVE DOCUMENTDB?
#   DocumentDB reads from disk — takes ~10-50ms per query.
#   Redis reads from RAM — takes ~0.1ms per query.
#
#   Flow WITHOUT Redis:
#     User opens app → API queries DocumentDB → waits 50ms → returns
#     1000 users do this = 1000 DB queries per second = DB overloaded
#
#   Flow WITH Redis:
#     User opens app → API checks Redis first (0.1ms hit)
#     If found (cache HIT) → returns immediately, DB not touched
#     If not found (cache MISS) → query DB, store result in Redis
#     Next user asking same thing → Redis hit, DB not touched
#
#   Result: 90% fewer DB queries, 10x faster responses.
#
# WHAT IS "REPLICATION GROUP"?
#   We create a Redis Replication Group — a cluster of 2 Redis nodes:
#     - Primary node: handles all reads and writes
#     - Replica node: copies everything from primary
#   If the primary node fails, the replica promotes automatically.
#   This is high availability — Redis never goes down.
# ─────────────────────────────────────────────────────────────────

# Subnet group — tells ElastiCache which subnets to use.
# Same concept as DocumentDB subnet group.
# Redis lives in the DATA subnets — isolated from internet.
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.environment}-redis-subnet-group"
  description = "ElastiCache Redis subnet group in data subnets"
  subnet_ids  = var.data_subnet_ids

  tags = {
    Name = "${var.environment}-redis-subnet-group"
  }
}

# Redis Replication Group — the actual Redis cluster with HA
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.environment}-redis"
  description          = "Redis cache for todo-app — reduces DB load and improves response time"

  engine         = "redis"
  engine_version = "7.0" # Redis version 7.0 — latest stable

  # cache.t3.micro has 0.5 GB RAM — enough for dev/test.
  # Use cache.r6g.large (6.38 GB) for production.
  node_type = "cache.t3.micro"

  # num_cache_clusters = 2: creates 1 primary + 1 replica.
  # If primary fails → replica becomes primary in ~60 seconds.
  num_cache_clusters = 2

  # automatic_failover_enabled: when primary fails, automatically
  # promote the replica. Without this, you'd need manual intervention.
  automatic_failover_enabled = true

  # multi_az_enabled: put primary in AZ-1 and replica in AZ-2.
  # If an entire data centre (AZ) fails, the other AZ's Redis is still up.
  multi_az_enabled = true

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.redis_sg_id]

  # Encrypt data stored in Redis.
  # at_rest_encryption_enabled = stored data on disk (if Redis persists to disk)
  # transit_encryption_enabled = data travelling between app and Redis
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # auth_token: a password required to connect to Redis.
  # Prevents unauthorized connections even within the VPC.
  # Must be 16-128 characters. Stored in Secrets Manager.
  auth_token = var.redis_auth_token

  # Maintenance window: when AWS can apply patches.
  # Pick a time when your traffic is lowest.
  maintenance_window = "sun:05:00-sun:06:00"

  tags = {
    Name = "${var.environment}-redis"
  }
}
