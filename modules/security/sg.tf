# ─────────────────────────────────────────────────────────────────
# modules/security/sg.tf
#
# PURPOSE: Creates Security Groups — virtual firewalls that control
# which ports and sources can communicate with each resource.
#
# TRAFFIC FLOW (each layer only accepts from the layer above it):
#
#   Internet
#     ↓  port 80/443 from anywhere
#   ALB  (alb_sg)
#     ↓  port 8080 from ALB only
#   App — EC2 / EKS  (app_sg)
#     ↓  port 27017 from App only        ← MongoDB port
#   DocumentDB  (db_sg)
#     ↓  port 6379 from App only         ← Redis port
#   ElastiCache  (redis_sg)
#     ↓  port 9092-9094 from App only    ← Kafka ports
#   MSK Kafka  (msk_sg)
#
# WHY REFERENCE SECURITY GROUPS INSTEAD OF IP ADDRESSES?
#   If you use CIDR (e.g. "allow 10.0.3.0/24"), you must update it
#   every time IPs change. Using security_groups = [alb_sg.id] means
#   "allow traffic from anything attached to alb_sg" — dynamic and safe.
# ─────────────────────────────────────────────────────────────────

# ── ALB Security Group ─────────────────────────────────────────────
# The load balancer faces the internet.
# Allow HTTP (80) and HTTPS (443) from anywhere (0.0.0.0/0).
# All other ports are blocked.
resource "aws_security_group" "alb_sg" {
  name        = "${var.environment}-alb-sg"
  description = "Allow HTTP/HTTPS from internet to ALB only"
  vpc_id      = var.vpc_id

  # Allow port 80 (HTTP) from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"         # BUG FIX: original had protocol = tcp (no quotes) → parse error
    cidr_blocks = ["0.0.0.0/0"] # 0.0.0.0/0 means "any IP address on the internet"
  }

  # Allow port 443 (HTTPS) from anywhere
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic — ALB needs to send responses back to browsers
  # and forward requests to backend targets (EKS/EC2)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"           # -1 means ALL protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-alb-sg"
  }
}

# ── App Security Group — EC2 (todo-api) and EKS nodes (todo-ui) ───
# Only the ALB is allowed to send traffic here.
# If someone tries to reach your EC2 directly from the internet,
# the security group blocks it — they must go through ALB.
resource "aws_security_group" "app_sg" {
  name        = "${var.environment}-app-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App traffic from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # only ALB can send here
  }

  # Allow all outbound — app needs to talk to DB, Redis, Kafka, and Secrets Manager
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-app-sg"
  }
}

# ── DB Security Group — DocumentDB (MongoDB) ──────────────────────
# Only the app layer can connect to the database.
# BUG FIX: Original had port 8080 for the DB — that is the APP port,
# not the database port. DocumentDB/MongoDB uses port 27017.
resource "aws_security_group" "db_sg" {
  name        = "${var.environment}-db-sg"
  description = "Allow MongoDB connections from app only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MongoDB port from app only"
    from_port       = 27017   # BUG FIX: was 8080 in original — MongoDB port is 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-db-sg"
  }
}

# ── Redis Security Group — ElastiCache ────────────────────────────
# Redis (cache) uses port 6379.
# Only the app layer can connect.
resource "aws_security_group" "redis_sg" {
  name        = "${var.environment}-redis-sg"
  description = "Allow Redis connections from app only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis port from app only"
    from_port       = 6379  # Redis always runs on 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-redis-sg"
  }
}

# ── MSK Security Group — Kafka ─────────────────────────────────────
# Kafka uses:
#   9092 = plaintext (we disable this — insecure)
#   9094 = TLS (encrypted — what we use)
#   9096 = SASL/TLS (if authentication is needed)
# We open 9092-9094 to cover both; MSK is configured to enforce TLS.
# Only the app layer can connect.
resource "aws_security_group" "msk_sg" {
  name        = "${var.environment}-msk-sg"
  description = "Allow Kafka connections from app only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Kafka TLS port from app only"
    from_port       = 9092
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-msk-sg"
  }
}
