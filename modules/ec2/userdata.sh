#!/bin/bash
# userdata.sh — Terraform template template
#
# IMPORTANT:
# Terraform replaces only specific placeholders defined in main.tf.
# Bash variables are written using $${VAR} so they are preserved for runtime.
# Do NOT write Terraform-style placeholders in comments.

set -e

echo "=== Starting todo-api setup at $$(date) ==="

# Step 1: Install dependencies
yum update -y
yum install -y java-17-amazon-corretto jq

echo "=== Java installed ==="

# Step 2: Get DocumentDB credentials from Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${secrets_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

DOCDB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
DOCDB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

echo "=== DocumentDB credentials fetched ==="

# Step 3: Get Redis token
REDIS_SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${redis_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text)

REDIS_TOKEN=$(echo "$REDIS_SECRET_JSON" | jq -r '.auth_token')

echo "=== Redis credentials fetched ==="

# Step 4: Download JAR from S3
mkdir -p /opt/todo-api
aws s3 cp s3://todo-app-artifacts-${environment}/todo-api-latest.jar \
  /opt/todo-api/todo-api.jar \
  --region "${aws_region}"

echo "=== JAR downloaded ==="

# Step 5: Download TLS cert
curl -o /opt/todo-api/global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

echo "=== TLS cert downloaded ==="

# Step 6: Write application.properties
cat > /opt/todo-api/application.properties << EOF
server.port=8080
spring.application.name=todo-api

spring.data.mongodb.uri=mongodb://$${DOCDB_USER}:$${DOCDB_PASS}@${docdb_endpoint}:27017/tododb?tls=true&tlsCAFile=/opt/todo-api/global-bundle.pem&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false
spring.data.mongodb.database=tododb

spring.data.redis.host=${redis_endpoint}
spring.data.redis.port=6379
spring.data.redis.password=$${REDIS_TOKEN}
spring.data.redis.ssl.enabled=true

spring.kafka.bootstrap-servers=${msk_brokers}
spring.kafka.security.protocol=SSL

management.endpoints.web.exposure.include=health,info,prometheus,metrics
management.endpoint.health.show-details=always

logging.level.com.todo=INFO
EOF

echo "=== application.properties written ==="

# Step 7: Create systemd service
cat > /etc/systemd/system/todo-api.service << 'SVCEOF'
[Unit]
Description=Todo API
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
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

# Step 8: Permissions
chown -R ec2-user:ec2-user /opt/todo-api

# Step 9: Start service
systemctl daemon-reload
systemctl enable todo-api
systemctl start todo-api

echo "=== Service started ==="
echo "=== Setup complete at $$(date) ==="

sleep 35
systemctl is-active --quiet todo-api && echo "=== HEALTH OK ===" || echo "=== HEALTH WARNING ==="