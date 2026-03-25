# WAF Web ACL — attach to ALB
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.env}-waf"
  description = "WAF for ${var.env} ALB"
  scope       = "REGIONAL"
  default_action {
    allow {}
  }

  # AWS Managed Rule — blocks common attacks
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 2
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.env}-waf-main" # Unique metric name
    sampled_requests_enabled   = true
  }
}

# Attach WAF to ALB
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# KMS key for encryption
resource "aws_kms_key" "main" {
  description             = "${var.env} encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = { Name = "${var.env}-kms" }
}

# Store DocumentDB credentials in Secrets Manager
resource "aws_secretsmanager_secret" "docdb_creds" {
  name       = "${var.env}/docdb/credentials-v2" # Added suffix to avoid naming conflicts
  kms_key_id = aws_kms_key.main.arn
}

resource "aws_secretsmanager_secret_version" "docdb_creds" {
  secret_id = aws_secretsmanager_secret.docdb_creds.id
  secret_string = jsonencode({
    username = "admin"
    password = var.docdb_password
  })
}