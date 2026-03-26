# ─────────────────────────────────────────────────────────────────
# modules/security/waf.tf
#
# PURPOSE: Creates three things that protect your application:
#
#  1. KMS Key — encryption key used to encrypt ALL sensitive data
#     (database, cache, disk volumes, secrets)
#
#  2. AWS Secrets Manager — safe storage for passwords and tokens
#     (DB password, Redis token). App fetches these at runtime.
#     They NEVER live in code or environment variables.
#
#  3. WAF (Web Application Firewall) — filters malicious internet
#     traffic BEFORE it reaches your ALB/app.
#     Blocks: SQL injection, XSS attacks, DDoS (rate limiting)
# ─────────────────────────────────────────────────────────────────

# ── KMS Key ────────────────────────────────────────────────────────
# KMS = Key Management Service.
# AWS uses encryption keys to scramble data so only authorised
# services can read it. KMS manages those keys for you.
#
# WHY DO WE NEED THIS?
#   Without encryption, if someone gets physical access to an AWS
#   data centre disk (extremely unlikely but possible), they could
#   read your data. Encryption makes the data unreadable without
#   the key. We use one KMS key for everything to keep it simple.
#
# enable_key_rotation = true:
#   AWS automatically replaces this key every year.
#   Old data encrypted with the old key still works (AWS keeps old
#   key versions). This is a security best practice.
resource "aws_kms_key" "main" {
  description             = "${var.environment} master encryption key"
  deletion_window_in_days = 30             # wait 30 days before deleting (safety net)
  enable_key_rotation     = true           # rotate key automatically every year

  tags = {
    Name = "${var.environment}-kms-key"
  }
}

# A human-readable name (alias) for the KMS key.
# Makes it easier to find in the AWS console.
resource "aws_kms_alias" "main" {
  name          = "alias/${var.environment}-todo-key"
  target_key_id = aws_kms_key.main.key_id
}

# ── Secrets Manager: DocumentDB credentials ────────────────────────
# AWS Secrets Manager is like a safe deposit box for passwords.
# Instead of putting the DB password in code (dangerous) or an
# environment variable (visible in ECS/EC2 console), we store it here.
# The app calls the Secrets Manager API at startup to get the password.
#
# Even if someone gets your code, they get nothing — the password
# is stored separately in Secrets Manager.
#
# kms_key_id: the secret itself is also encrypted using our KMS key.
resource "aws_secretsmanager_secret" "docdb_creds" {
  name                    = "${var.environment}/todo/docdb-credentials"
  description             = "DocumentDB master username and password for todo-api"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7 # can recover the secret for 7 days after deletion

  tags = {
    Name = "${var.environment}-docdb-secret"
  }
}

# Store the actual username and password in the secret.
# We use jsonencode so the app can parse it:
# {"username":"admin","password":"..."}
resource "aws_secretsmanager_secret_version" "docdb_creds" {
  secret_id = aws_secretsmanager_secret.docdb_creds.id
  secret_string = jsonencode({
    username = "todoadmin"
    password = var.docdb_password # value comes from terraform.tfvars — never hardcoded
  })
}

# ── Secrets Manager: Redis auth token ─────────────────────────────
# Same pattern — Redis password stored in Secrets Manager.
resource "aws_secretsmanager_secret" "redis_creds" {
  name                    = "${var.environment}/todo/redis-credentials"
  description             = "ElastiCache Redis authentication token for todo-api"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7

  tags = {
    Name = "${var.environment}-redis-secret"
  }
}

resource "aws_secretsmanager_secret_version" "redis_creds" {
  secret_id = aws_secretsmanager_secret.redis_creds.id
  secret_string = jsonencode({
    auth_token = var.redis_auth_token
  })
}

# ── WAF Web ACL ────────────────────────────────────────────────────
# WAF = Web Application Firewall.
# It sits in front of the ALB and inspects every incoming request
# BEFORE it reaches your application.
#
# scope = "REGIONAL": applies to resources in one region (our ALB).
# The other option is "CLOUDFRONT" (for global CDN).
#
# default_action { allow {} }: by default allow all traffic.
# Rules below then BLOCK specific bad patterns.
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.environment}-waf"
  description = "WAF for todo-app ALB blocks common attacks and rate limits"
  scope       = "REGIONAL"

  # Default: allow all traffic unless a rule below blocks it
  default_action {
    allow {}
  }

  # ── Rule 1: AWS Managed Common Rules ─────────────────────────────
  # AWS has a pre-built ruleset that blocks the most common web attacks:
  #   - SQL Injection: attacker sends ' OR 1=1 -- to bypass login
  #   - XSS: attacker injects <script>steal_cookies()</script>
  #   - Known bad IPs: AWS maintains a list of known attacker IPs
  #
  # override_action { none {} } = use the rules as-is (block when triggered)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {} # "none" means: use the action defined in the managed rule (usually block)
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true # send metrics to CloudWatch so we can see attacks
      metric_name                = "${var.environment}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 2: Rate Limiting ─────────────────────────────────────────
  # If a single IP sends more than 1000 requests in 5 minutes, block it.
  # WHY? A normal user opens maybe 20 pages. 1000 requests = bot or DDoS attack.
  # This protects your app from being overwhelmed.
  #
  # Example: someone writes a script that calls your API 10,000 times per minute.
  # Without WAF: your EC2 crashes. With WAF: they get blocked at edge, app is fine.
  rule {
    name     = "RateLimitRule"
    priority = 2

    action {
      block {} # block requests that exceed the rate limit
    }

    statement {
      rate_based_statement {
        limit              = 1000           # max requests per 5 minutes per IP
        aggregate_key_type = "IP"           # track by source IP address
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Overall visibility config for the WAF ACL itself
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-waf-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.environment}-waf"
  }
}

# ── Attach WAF to ALB ─────────────────────────────────────────────
# The WAF ACL only does something when attached to a resource.
# We attach it to the ALB so all traffic going into the ALB
# is first inspected by WAF.
# This resource is only created when alb_arn is provided
# (after the ALB module runs).
resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.alb_arn != "" ? 1 : 0  # only create if alb_arn is set
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
