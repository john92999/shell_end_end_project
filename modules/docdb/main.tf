# ─────────────────────────────────────────────────────────────────
# modules/docdb/main.tf
#
# PURPOSE: Creates AWS DocumentDB — which IS your MongoDB.
#
# WHAT IS DOCUMENTDB?
#   DocumentDB is AWS's managed database service that is 100%
#   compatible with MongoDB. Your todo-api code uses MongoDB
#   driver and MongoDB connection strings — they work unchanged.
#   The difference is that AWS manages the server:
#     - AWS handles backups automatically
#     - AWS patches the database engine
#     - AWS replaces failed instances automatically
#   You never SSH into a MongoDB server — it just works.
#
# WHY NOT RUN MONGODB ON EC2?
#   You could install MongoDB on an EC2 instance yourself, but:
#     - You must handle backups manually
#     - If the EC2 crashes, MongoDB is gone until you restart it
#     - You must patch MongoDB yourself (security risk if you forget)
#   DocumentDB solves all of this automatically.
#
# CLUSTER vs INSTANCE (this confused you):
#   CLUSTER = the overall MongoDB "group" — manages storage,
#             replication, and gives you the endpoint URL.
#             It holds your data across multiple copies.
#   INSTANCE = one actual compute node that executes queries.
#             Cluster alone cannot serve queries — needs instances.
#
#   Think of it like a restaurant:
#     Cluster = the restaurant (address, kitchen, storage)
#     Instance = a cook inside the restaurant (does the actual work)
#   If there is no cook (instance), the restaurant cannot serve food.
#   We create 2 instances so if one fails, the other keeps serving.
# ─────────────────────────────────────────────────────────────────

# ── Subnet Group ──────────────────────────────────────────────────
# A subnet group tells DocumentDB which subnets it can use.
# WHY? DocumentDB creates network interfaces (private IPs) inside
# your VPC so your app can connect to it.
# We give it the DATA subnets — the most isolated layer of the network.
# DocumentDB will spread its instances across these subnets (AZs)
# so if one AZ fails, the other keeps serving.
resource "aws_docdb_subnet_group" "main" {
  name        = "${var.environment}-docdb-subnet-group"
  description = "DocumentDB subnet group uses data subnets for maximum isolation"
  subnet_ids  = var.data_subnet_ids

  tags = {
    Name = "${var.environment}-docdb-subnet-group"
  }
}

# ── Cluster Parameter Group ────────────────────────────────────────
# A parameter group is a collection of settings for the database engine.
# Here we enforce TLS — all connections MUST be encrypted.
# WHY? Without TLS, data travelling between your app and MongoDB
# is plain text. Anyone who can intercept VPC traffic can read it.
resource "aws_docdb_cluster_parameter_group" "main" {
  name        = "${var.environment}-docdb-params"
  family      = "docdb5.0" # DocumentDB engine version 5.0 (MongoDB 5.0 compatible)
  description = "Force TLS on all DocumentDB connections"

  parameter {
    name  = "tls"
    value = "enabled" # all connections must use TLS encryption
  }

  tags = {
    Name = "${var.environment}-docdb-params"
  }
}

# ── DocumentDB Cluster ─────────────────────────────────────────────
# This is the "restaurant building" — it manages storage and replication.
# Your app connects to the cluster_endpoint (the address of the cluster).
resource "aws_docdb_cluster" "main" {
  cluster_identifier = "${var.environment}-todo-docdb"
  engine             = "docdb"

  # Master username and password — app uses these to authenticate.
  # Password comes from terraform.tfvars — never hardcoded here.
  master_username = "todoadmin"
  master_password = var.docdb_password

  # Which subnets DocumentDB can use
  db_subnet_group_name = aws_docdb_subnet_group.main.name

  # Which security group — only app_sg can connect (port 27017)
  vpc_security_group_ids = [var.db_sg_id]

  # Encrypt all data at rest using our KMS key.
  # "At rest" means data stored on disk — if someone stole the
  # physical disk they still cannot read it.
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Use the TLS-enforcing parameter group we created above
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.main.name

  # Backup: keep daily snapshots for 7 days.
  # If you accidentally delete data, you can restore to any point
  # in the last 7 days.
  backup_retention_period   = 7
  preferred_backup_window   = "02:00-04:00" # backup at 2-4 AM IST when traffic is low

  # Prevent accidental deletion with terraform destroy.
  # You must set this to false before you can delete the cluster.
  deletion_protection = false # set to true in production!

  # Take a final snapshot when deleted (won't apply if deletion_protection is true)
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.environment}-docdb-final-snapshot"

  tags = {
    Name = "${var.environment}-docdb"
  }
}

# ── DocumentDB Instances ───────────────────────────────────────────
# These are the "cooks" — they actually execute your MongoDB queries.
# We create 2 instances:
#   - Instance 0: PRIMARY — handles all reads and writes
#   - Instance 1: REPLICA — handles reads, and promotes to primary
#                           automatically if instance 0 fails
#
# count = 2 creates both with one block.
# The identifier uses count.index (0, 1) to give unique names.
resource "aws_docdb_cluster_instance" "main" {
  count              = 2
  identifier         = "${var.environment}-docdb-instance-${count.index}"
  cluster_identifier = aws_docdb_cluster.main.id

  # db.t3.medium is suitable for dev/test. Use db.r5.large for production.
  instance_class = "db.t3.medium"

  tags = {
    Name = "${var.environment}-docdb-instance-${count.index}"
  }
}
