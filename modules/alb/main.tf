# ─────────────────────────────────────────────────────────────────
# modules/alb/main.tf
#
# FIX APPLIED: HTTPS listener is now conditional.
#
# WHY WAS IT BROKEN?
#   The HTTPS listener used certificate_arn = var.acm_certificate_arn
#   When acm_certificate_arn = "" (empty string, the default),
#   AWS rejects the listener creation with:
#     "CertificateArn cannot be empty"
#
#   For dev/testing without a real domain, we just use HTTP on port 80.
#   For production, set acm_certificate_arn in terraform.tfvars to
#   a real ACM certificate ARN and the HTTPS listener is created.
#
# HOW THE FIX WORKS:
#   count = var.acm_certificate_arn != "" ? 1 : 0
#   This means: if you provided a cert ARN → create the HTTPS listener (count=1)
#              if cert ARN is empty → skip the HTTPS listener (count=0)
# ─────────────────────────────────────────────────────────────────

# ── Application Load Balancer ──────────────────────────────────────
# The ALB is the single entry point for all user traffic.
# It lives in PUBLIC subnets so browsers can reach it.
# Everything behind it (EC2, EKS pods) is in PRIVATE subnets.
resource "aws_lb" "alb" {
  name               = "${var.environment}-todo-alb"
  load_balancer_type = "application"    # ALB = Layer 7, understands HTTP paths
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]

  # Security hardening: reject requests with malformed HTTP headers.
  # Prevents certain HTTP smuggling attacks at the edge.
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.environment}-todo-alb"
  }
}

# ── Attach WAF to ALB ─────────────────────────────────────────────
# WAF (Web Application Firewall) filters all traffic BEFORE it
# reaches the ALB listeners. Blocks SQL injection, XSS, and DDoS.
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = var.waf_acl_arn
}

# ── Target Group: todo-api (EC2 Auto Scaling Group) ───────────────
# A Target Group is the list of backend servers the ALB routes to.
# The ALB health-checks each EC2 instance every 30 seconds.
# If /actuator/health returns 200 → instance is healthy → gets traffic.
# If it fails twice → instance is removed from rotation automatically.
resource "aws_lb_target_group" "api" {
  name        = "${var.environment}-api-tg"
  port        = 8080          # Spring Boot todo-api listens on 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"    # targets are EC2 instances (not pods)

  health_check {
    path                = "/actuator/health"  # Spring Boot health endpoint
    port                = "traffic-port"      # same port as target (8080)
    protocol            = "HTTP"
    interval            = 30                  # check every 30 seconds
    timeout             = 5                   # 5 second timeout per check
    healthy_threshold   = 2                   # 2 successes = healthy
    unhealthy_threshold = 2                   # 2 failures = remove from ALB
    matcher             = "200"               # HTTP 200 = healthy
  }

  tags = {
    Name = "${var.environment}-api-tg"
  }
}

# ── Target Group: todo-ui (EKS Kubernetes pods) ───────────────────
# For EKS pods we use target_type = "ip" because pods get individual
# IP addresses. The AWS Load Balancer Controller registers/deregisters
# pod IPs automatically as pods start and stop.
resource "aws_lb_target_group" "ui" {
  name        = "${var.environment}-ui-tg"
  port        = 3000          # React/nginx todo-ui listens on 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"          # register pod IPs directly (required for EKS)

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "${var.environment}-ui-tg"
  }
}

# ── HTTP Listener (port 80) ────────────────────────────────────────
# For dev (no SSL cert): HTTP on port 80 forwards directly to UI.
# For prod (with SSL cert): this redirects to HTTPS instead.
# count controls which behaviour applies based on whether a cert is set.

# Dev mode: HTTP → forward to UI (no redirect, no cert needed)
resource "aws_lb_listener" "http_dev" {
  count             = var.acm_certificate_arn == "" ? 1 : 0
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  # Default: all traffic to the UI target group (todo-ui on EKS)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }
}

# Prod mode: HTTP → redirect to HTTPS (only created when cert is set)
resource "aws_lb_listener" "http_redirect" {
  count             = var.acm_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"  # permanent redirect
    }
  }
}

# ── HTTPS Listener (port 443) ──────────────────────────────────────
# FIX: count = 0 when acm_certificate_arn is empty.
# Without this fix, Terraform would try to create the listener with
# an empty certificate_arn and AWS would reject it.
# Only created when you set acm_certificate_arn in terraform.tfvars.
resource "aws_lb_listener" "https" {
  count             = var.acm_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"

  # Strong TLS policy — disables TLS 1.0 and 1.1 (insecure old versions)
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = var.acm_certificate_arn

  # Default: send to UI
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }
}

# ── Routing Rule: /api/* → EC2 backend ────────────────────────────
# When URL starts with /api/, the ALB sends the request to the
# EC2 API target group instead of the EKS UI target group.
# This rule applies to both the HTTP dev listener and HTTPS prod listener.
#
# Path pattern:
#   /api/todos    → EC2 (API)
#   /api/todos/1  → EC2 (API)
#   /             → EKS (UI, default)
#   /login        → EKS (UI, default)

# API route for dev (HTTP)
resource "aws_lb_listener_rule" "api_route_http" {
  count        = var.acm_certificate_arn == "" ? 1 : 0
  listener_arn = aws_lb_listener.http_dev[0].arn
  priority     = 1

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# API route for prod (HTTPS)
resource "aws_lb_listener_rule" "api_route_https" {
  count        = var.acm_certificate_arn != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 1

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
