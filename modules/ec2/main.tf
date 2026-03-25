resource "aws_launch_template""api" {
  name_prefix   = "${var.env}-todo-api-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.small"

  # No public IP — accessed only via ALB
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.app_sg_id]
  }

  iam_instance_profile { name = var.ec2_instance_profile }

  # EBS root volume encrypted
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install java-17 -y

    # Pull credentials from Secrets Manager (not hardcoded)
    SECRET=$(aws secretsmanager get-secret-value \
      --secret-id dev/docdb/credentials \
      --region ap-south-1 \
      --query SecretString --output text)

    export DOCDB_USER=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin).get(str(chr(117)+chr(115)+chr(101)+chr(114)+chr(110)+chr(97)+chr(109)+chr(101))))")
    # (simplified: parse username and password fields from the JSON secret)

    # Pull app jar from S3 or ECR (use ECR for Docker)
    aws s3 cp s3://todo-app-artifacts/todo-api.jar /opt/todo-api.jar

    # Run the app
    java -jar /opt/todo-api.jar &
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.env}-todo-api" }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group""api" {
  name             = "${var.env}-api-asg"
  desired_capacity = 2
  min_size         = 2
  max_size         = 6
  vpc_zone_identifier = var.private_subnet_ids   # private subnets across 2 AZs

  launch_template {
    id      = aws_launch_template.api.id
    version = "$Latest"
  }

  # Attach to ALB target group for health checking
  target_group_arns         = [var.api_target_group_arn]
  health_check_type         = "ELB"    # use ALB health check, not EC2 status check
  health_check_grace_period = 120

  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }

  tag { key="Name"; value="${var.env}-todo-api"; propagate_at_launch=true }
}

# Scale-out policy when CPU > 70%
resource "aws_autoscaling_policy""scale_out" {
  name                   = "scale-out"
  autoscaling_group_name = aws_autoscaling_group.api.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
