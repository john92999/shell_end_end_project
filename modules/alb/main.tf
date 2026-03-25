resource "aws_lb""alb" {
  name               = "${var.env}-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids   # ALB MUST be in public subnets
  security_groups    = [var.alb_sg_id]
  drop_invalid_header_fields = true    # security best practice
  tags = { Name = "${var.env}-alb" }
}

# Target Group for todo-api (EC2)
resource "aws_lb_target_group""api" {
  name     = "${var.env}-api-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_autoscaling_attachment""api" {
  autoscaling_group_name = var.api_asg_name
  lb_target_group_arn    = aws_lb_target_group.api.arn
}

resource "aws_lb_listener""https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_cert_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb_listener""http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect { port="443"; protocol="HTTPS"; status_code="HTTP_301" }
  }
}

resource "aws_lb""nlb" {
  name               = "${var.env}-nlb"
  load_balancer_type = "network"
  internal           = true   # internal NLB — not internet-facing
  subnets            = var.private_subnet_ids
  tags = { Name = "${var.env}-nlb" }
}
