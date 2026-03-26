# modules/alb/outputs.tf

output "alb_dns_name" {
  description = "DNS name to access the app. Paste this in your browser."
  value       = aws_lb.alb.dns_name
}

output "alb_arn" {
  description = "ALB ARN — used to attach WAF to it."
  value       = aws_lb.alb.arn
}

output "api_target_group_arn" {
  description = "Target group ARN for todo-api. EC2 ASG registers its instances here."
  value       = aws_lb_target_group.api.arn
}

output "ui_target_group_arn" {
  description = "Target group ARN for todo-ui. EKS Ingress controller registers pod IPs here."
  value       = aws_lb_target_group.ui.arn
}
