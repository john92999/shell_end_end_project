#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# userdata.sh
#
# PURPOSE: This script runs ONCE when a new EC2 instance starts.
# It sets up the environment and starts the todo-api application.
#
# HOW IT WORKS:
#   AWS injects this script into the EC2 instance at first boot.
#   It runs as the root user before anyone logs in.
#   Terraform uses templatefile() to insert the variable values
#   (like docdb_endpoint) at apply time.
#
# VARIABLES from Terraform templatefile():
#   ${environment}    → "dev" or "prod"
#   ${aws_region}     → "ap-south-1"
#   ${secrets_arn}    → ARN of the Secrets Manager secret
#   ${docdb_endpoint} → DocumentDB connection endpoint
#   ${redis_endpoint} → Redis connection endpoint
#   ${msk_brokers}    → Kafka broker connection strings
# ─────────────────────────────────────────────────────────────────

set -e  # exit immediately if any command fails (catches errors early)

echo "=== Starting todo-api setup at $(date) ==="

# ── Step 1: Update OS and install Java 17 ─────────────────────────
# yum = package manager for Amazon Linux (like apt for Ubuntu)
yum update -y
yum install -y java-17-amazon-corretto  # Java 17 LTS — runs Spring Boot
yum install -y aws-cli jq               # aws cli (to call Secrets Manager) and jq (JSON parser)

echo "=== Java installed: $(java -version 2>&1) ==="

# ── Step 2: Fetch credentials from AWS Secrets Manager ────────────
# Instead of hardcoding passwords, we fetch them from Secrets Manager.
# The EC2 instance's IAM role allows it to call this API — no keys needed.
#
# aws secretsmanager get-secret-value: retrieves the secret
# --query SecretString: extracts only the JSON string value
# --output text: returns plain text (not JSON wrapper)
# jq -r '.fieldname': parses the JSON and extracts a specific field
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${secrets_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

# Parse username and password from the JSON secret
DOCDB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
DOCDB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

echo "=== Credentials fetched from Secrets Manager ==="

# ── Step 3: Download the application JAR from S3 ──────────────────
# The CI/CD pipeline (Jenkins) builds the JAR and uploads it to S3.
# We download the latest version here.
# In a Docker-based approach, you would pull from ECR instead.
mkdir -p /opt/todo-api
aws s3 cp s3://todo-app-artifacts-${environment}/todo-api-latest.jar \
  /opt/todo-api/todo-api.jar \
  --region "${aws_region}"

echo "=== Application JAR downloaded ==="

# ── Step 4: Create application configuration ──────────────────────
# Spring Boot reads application.properties at startup.
# We write it here so the app knows how to connect to:
#   - DocumentDB (MongoDB connection string)
#   - Redis (cache)
#   - MSK (Kafka)
#
# IMPORTANT: DocumentDB requires TLS and a special MongoDB URI format.
# The ?tls=true&tlsCAFile=... part enables encrypted connections.
cat > /opt/todo-api/application.properties << EOF
# Server port
server.port=8080
spring.application.name=todo-api

# ── DocumentDB (MongoDB) connection ──────────────────────────────
# mongodb:// URI format — same as standard MongoDB connection string
# DocumentDB requires TLS — the CA certificate is bundled with the app
spring.data.mongodb.uri=mongodb://${DOCDB_USER}:${DOCDB_PASS}@${docdb_endpoint}:27017/tododb?ssl=true&ssl_ca_certs=/opt/todo-api/rds-combined-ca-bundle.pem&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false
spring.data.mongodb.database=tododb

# ── Redis connection ───────────────────────────────────────────────
spring.data.redis.host=${redis_endpoint}
spring.data.redis.port=6379
spring.data.redis.password=${redis_auth_token}
spring.data.redis.ssl.enabled=true

# ── Kafka (MSK) connection ─────────────────────────────────────────
spring.kafka.bootstrap-servers=${msk_brokers}
spring.kafka.security.protocol=SSL
spring.kafka.consumer.group-id=todo-api-group
spring.kafka.consumer.auto-offset-reset=earliest

# ── Actuator (health checks for ALB) ──────────────────────────────
management.endpoints.web.exposure.include=health,info,prometheus,metrics
management.endpoint.health.show-details=always

# ── Logging (structured JSON for ELK) ─────────────────────────────
logging.level.com.todo=INFO
EOF

# ── Step 5: Download the DocumentDB TLS certificate ───────────────
# DocumentDB requires a TLS certificate to verify the connection is genuine.
# AWS provides this certificate file (rds-combined-ca-bundle.pem).
# Without this, the MongoDB driver will reject the connection.
curl -o /opt/todo-api/rds-combined-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

echo "=== DocumentDB TLS certificate downloaded ==="

# ── Step 6: Create a systemd service ──────────────────────────────
# systemd is the Linux process manager. Creating a service file means:
#   - The app starts automatically when the EC2 instance reboots
#   - systemd restarts the app if it crashes (Restart=always)
#   - You can check status with: systemctl status todo-api
cat > /etc/systemd/system/todo-api.service << EOF
[Unit]
Description=Todo API Spring Boot Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/todo-api
ExecStart=/usr/bin/java \
  -Xms256m -Xmx512m \
  -Dspring.config.location=/opt/todo-api/application.properties \
  -jar /opt/todo-api/todo-api.jar
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ── Step 7: Start the application ─────────────────────────────────
systemctl daemon-reload        # tell systemd to load the new service file
systemctl enable todo-api      # start automatically on reboot
systemctl start todo-api       # start now

echo "=== todo-api started ==="
echo "=== Setup complete at $(date) ==="

# ── Step 8: Health check wait ─────────────────────────────────────
# Wait for the app to start before the ALB starts checking health.
# The ASG's health_check_grace_period (180s) handles this,
# but we also wait here as a safety measure.
sleep 30
systemctl status todo-api
