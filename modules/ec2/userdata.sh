#!/bin/bash
# userdata.sh — Terraform templatefile for EC2 todo-api bootstrap
#
# IMPORTANT — two kinds of variables in this file:
#   ${var}    = Terraform replaces this BEFORE the script runs (build time)
#   $${var}   = becomes ${var} at runtime — a real bash variable
#   $$(cmd)   = becomes $(cmd) at runtime — a real bash subshell
#
# Terraform variables available (injected via templatefile()):
#   ${environment}     ${aws_region}      ${secrets_arn}
#   ${redis_secret_arn} ${docdb_endpoint} ${redis_endpoint}
#   ${msk_brokers}     ${artifact_bucket}

set -euo pipefail

# ── Logging: all output goes to /var/log/user-data.log AND the journal ──
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== [1/9] Starting todo-api setup at $$(date) ==="
echo "=== Environment : ${environment} ==="
echo "=== Region      : ${aws_region} ==="
echo "=== Artifact    : s3://${artifact_bucket}/todo-api-latest.jar ==="

# ── Step 1: Install dependencies ────────────────────────────────────────
echo "=== [1/9] Installing Java 17 and jq ==="
yum update -y
yum install -y java-17-amazon-corretto jq
echo "=== Java version: $$(java -version 2>&1 | head -1) ==="

# ── Step 2: Fetch DocumentDB credentials from Secrets Manager ───────────
echo "=== [2/9] Fetching DocumentDB credentials ==="
SECRET_JSON=$$(aws secretsmanager get-secret-value \
  --secret-id "${secrets_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

DOCDB_USER=$$(echo "$$SECRET_JSON" | jq -r '.username')
DOCDB_PASS=$$(echo "$$SECRET_JSON" | jq -r '.password')
echo "=== DocumentDB user: $$DOCDB_USER ==="

# ── Step 3: Fetch Redis auth token from Secrets Manager ─────────────────
echo "=== [3/9] Fetching Redis credentials ==="
REDIS_SECRET_JSON=$$(aws secretsmanager get-secret-value \
  --secret-id "${redis_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

REDIS_TOKEN=$$(echo "$$REDIS_SECRET_JSON" | jq -r '.auth_token')
echo "=== Redis token fetched ==="

# ── Step 4: Download JAR from S3 ────────────────────────────────────────
echo "=== [4/9] Downloading JAR from S3 ==="
mkdir -p /opt/todo-api

# Retry up to 3 times — transient S3 errors are common at boot
for attempt in 1 2 3; do
  echo "=== S3 download attempt $$attempt ==="
  aws s3 cp s3://${artifact_bucket}/todo-api-latest.jar \
    /opt/todo-api/todo-api.jar \
    --region "${aws_region}" && break
  echo "=== Attempt $$attempt failed, retrying in 10s ==="
  sleep 10
done

# Confirm JAR exists and has non-zero size
if [[ ! -s /opt/todo-api/todo-api.jar ]]; then
  echo "=== FATAL: JAR download failed or file is empty ==="
  exit 1
fi
echo "=== JAR size: $$(du -sh /opt/todo-api/todo-api.jar) ==="

# ── Step 5: Download DocumentDB TLS certificate ─────────────────────────
echo "=== [5/9] Downloading DocumentDB TLS cert ==="
curl --retry 3 --retry-delay 5 -o /opt/todo-api/global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
echo "=== TLS cert size: $$(wc -c < /opt/todo-api/global-bundle.pem) bytes ==="

# ── Step 6: Write application.properties ────────────────────────────────
echo "=== [6/9] Writing application.properties ==="
cat > /opt/todo-api/application.properties << EOF
server.port=8080
spring.application.name=todo-api

# DocumentDB (MongoDB-compatible)
spring.data.mongodb.uri=mongodb://$${DOCDB_USER}:$${DOCDB_PASS}@${docdb_endpoint}:27017/tododb?tls=true&tlsCAFile=/opt/todo-api/global-bundle.pem&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false
spring.data.mongodb.database=tododb

# ElastiCache Redis
spring.data.redis.host=${redis_endpoint}
spring.data.redis.port=6379
spring.data.redis.password=$${REDIS_TOKEN}
spring.data.redis.ssl.enabled=true

# MSK Kafka
spring.kafka.bootstrap-servers=${msk_brokers}
spring.kafka.security.protocol=SSL

# Actuator — exposes /actuator/health for ALB health checks
management.endpoints.web.exposure.include=health,info,prometheus,metrics
management.endpoint.health.show-details=always

logging.level.com.todo=INFO
EOF
echo "=== application.properties written ==="

# ── Step 7: Create systemd service unit ─────────────────────────────────
echo "=== [7/9] Creating systemd service ==="
cat > /etc/systemd/system/todo-api.service << 'SVCEOF'
[Unit]
Description=Todo API Spring Boot Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/todo-api
ExecStart=/usr/bin/java \
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -Dspring.config.location=/opt/todo-api/application.properties \
  -jar /opt/todo-api/todo-api.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=todo-api

[Install]
WantedBy=multi-user.target
SVCEOF

# ── Step 8: Set ownership and permissions ───────────────────────────────
echo "=== [8/9] Setting permissions ==="
chown -R ec2-user:ec2-user /opt/todo-api
chmod 600 /opt/todo-api/application.properties   # credentials file — restrict read

# ── Step 9: Start the service ────────────────────────────────────────────
echo "=== [9/9] Starting todo-api service ==="
systemctl daemon-reload
systemctl enable todo-api
systemctl start todo-api

# Wait for Spring Boot to finish starting (it takes ~30-60 seconds)
echo "=== Waiting 60s for Spring Boot to initialise ==="
sleep 60

# Final health check — confirms the app is running before ASG checks begin
if systemctl is-active --quiet todo-api; then
  echo "=== HEALTH OK: todo-api service is running ==="
  # Probe the actuator endpoint directly
  curl -sf http://localhost:8080/actuator/health \
    && echo "=== ACTUATOR OK ===" \
    || echo "=== ACTUATOR WARNING: service up but /actuator/health not responding yet ==="
else
  echo "=== HEALTH FAIL: todo-api service is NOT running ==="
  journalctl -u todo-api --no-pager -n 50
  exit 1
fi

echo "=== Setup complete at $$(date) ==="