# modules/ec2/outputs.tf

output "asg_name" {
  description = "Auto Scaling Group name. Use this in Jenkins to trigger instance refresh."
  value       = aws_autoscaling_group.api.name
}

output "launch_template_id" {
  description = "Launch template ID. Jenkins updates this with new AMI/image on each deploy."
  value       = aws_launch_template.api.id
}
