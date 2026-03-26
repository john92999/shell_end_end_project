# ─────────────────────────────────────────────────────────────────
# modules/alb/main.tf
#
# PURPOSE: Creates the Application Load Balancer (ALB).
#
# WHAT IS AN ALB?
#   ALB = Application Load Balancer.
#   It is the entry point for all user traffic.
#   It receives requests from browsers and routes them to the
#   correct backend service.
#
#   ROUTING RULES:
#     /       → send to EKS (todo-ui React app)
#     /api/*  → send to EC2 Auto Scaling Group (todo-api Java backend)
#
# ALB vs NLB:
#   ALB (Layer 7): understands HTTP. Can read URL paths, headers,
#                  cookies. Routes / to UI and /api to backend.
#                  This is what we use for the todo app.
#
#   NLB (Layer 4): only sees TCP packets. Ultra-fast (microseconds).
#                  Used for Kafka (TCP protocol) or gaming/streaming.
#                  We create an internal NLB for MSK (optional).
#
# WHY PUBLIC SUBNETS?
#   The ALB is the only resource that faces the internet.
#   It must be in public subnets so browsers can reach it.
#   Everything behind it (EC2, EKS) is in private subnets.
# ─────────────────────────────────────────────────────────────────

# ── Application Load Balancer ──────────────────────────────────────
resource "aws_lb" "alb" {
  name               = "${var.environment}-todo-alb"
  load_balancer_type = "application"

  # ALB must be in PUBLIC subnets — users connect to it from internet
  subnets = var.public_subnet_ids

  # The ALB security group only allows 80/443 from internet
  security_groups = [var.alb_sg_id]

  # Security setting: drop requests with invalid HTTP headers.
  # Prevents certain HTTP smuggling attacks.
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.environment}-todo-alb"
  }
}

# ── Target Group: todo-api (EC2) ───────────────────────────────────
# A Target Group is a list of servers that ALB sends traffic to.
# Think of it as: "these are the EC2 instances handling /api requests"
#
# Health checks: ALB calls /health every 30s on each EC2 instance.
# If 2 consecutive checks fail → remove that instance from rotation.
# If 2 consecutive checks pass → add it back.
# This ensures users never get sent to a broken server.
resource "aws_lb_target_group" "api" {
  name        = "${var.environment}-api-tg"
  port        = 8080     # todo-api listens on port 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance" # targets are EC2 instances

  health_check {
    path                = "/actuator/health" # Spring Boot health endpoint
    port                = "traffic-port"     # same port as target (8080)
    protocol            = "HTTP"
    interval            = 30                 # check every 30 seconds
    timeout             = 5                  # wait 5 seconds for response
    healthy_threshold   = 2                  # 2 successes = healthy
    unhealthy_threshold = 2                  # 2 failures = unhealthy → remove from ALB
    matcher             = "200"              # HTTP 200 = healthy
  }

  tags = {
    Name = "${var.environment}-api-tg"
  }
}

# ── Target Group: todo-ui (EKS/Kubernetes) ────────────────────────
# For EKS, we use target_type = "ip" because Kubernetes pods
# get their own IPs and can move between nodes.
# "ip" type allows the ALB Ingress Controller to register
# pod IPs directly instead of node IPs.
resource "aws_lb_target_group" "ui" {
  name        = "${var.environment}-ui-tg"
  port        = 3000     # todo-ui React app listens on port 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"     # register pod IPs (needed for EKS/Kubernetes)

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

# ── HTTP Listener: Redirect to HTTPS ──────────────────────────────
# All HTTP (port 80) traffic is redirected to HTTPS (port 443).
# WHY? HTTP is unencrypted. You never want user data (passwords,
# todo items) travelling unencrypted across the internet.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301" # 301 = permanent redirect
    }
  }
}

# ── HTTPS Listener: Route traffic ─────────────────────────────────
# All HTTPS (port 443) traffic goes through here.
# Default action sends traffic to the UI (todo-ui on EKS).
# Path-based rules send /api/* to todo-api on EC2.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"

  # Use a strong TLS policy — disables old insecure TLS versions
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # Your SSL certificate — managed by AWS Certificate Manager (ACM).
  # Get a free certificate from ACM for your domain.
  certificate_arn = var.acm_certificate_arn

  # Default: send to UI (todo-ui)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }
}

# ── Listener Rule: Route /api/* to EC2 backend ────────────────────
# When the URL starts with /api, send to the API target group (EC2).
# This rule has priority 1 — checked before the default rule.
resource "aws_lb_listener_rule" "api_route" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  condition {
    path_pattern {
      values = ["/api/*"] # matches any URL starting with /api/
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
