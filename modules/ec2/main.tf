# ─────────────────────────────────────────────────────────────────
# modules/ec2/main.tf
#
# PURPOSE: Creates the EC2 Auto Scaling Group that runs todo-api.
#
# WHY EC2 (not EKS) FOR THE API?
#   This is a design choice to show a mixed architecture.
#   In the real world many teams run their API on EC2 when:
#     - The app is a JAR file not yet containerised
#     - The team is more comfortable with EC2 than Kubernetes
#   For your interview, this shows you understand BOTH deployment models.
#
# KEY COMPONENTS:
#
#   Launch Template:
#     A blueprint for your EC2 instance. Defines: AMI (operating system),
#     instance type (size), security group, startup script, etc.
#     Every new instance created by ASG uses this template.
#
#   Auto Scaling Group (ASG):
#     Keeps a minimum number of EC2 instances running at all times.
#     Adds more when CPU is high (scale out).
#     Removes extras when CPU is low (scale in).
#     Replaces unhealthy instances automatically.
#
#   User Data Script:
#     A shell script that runs ONCE when a new EC2 instance starts.
#     We use it to: install Java, fetch credentials from Secrets Manager,
#     download the app JAR from S3, and start the Spring Boot server.
#
#   Instance Refresh:
#     When you update the Launch Template (new app version),
#     ASG replaces old instances with new ones one at a time.
#     50% must remain healthy during the replacement — zero downtime.
# ─────────────────────────────────────────────────────────────────

# ── Data Source: Get Latest Amazon Linux 2023 AMI ─────────────────
# AMI = Amazon Machine Image = the OS template for EC2 instances.
# Instead of hardcoding an AMI ID (which changes per region/version),
# we query AWS to get the latest Amazon Linux 2023 AMI automatically.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"] # only official Amazon-published AMIs

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"] # Amazon Linux 2023 pattern
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"] # HVM = hardware-assisted virtualisation (standard for modern instances)
  }
}

# ── Launch Template ────────────────────────────────────────────────
# The blueprint for each EC2 instance in the ASG.
# name_prefix means Terraform adds a random suffix: "dev-todo-api-abc123"
# This allows new versions to be created without naming conflicts.
resource "aws_launch_template" "api" {
  name_prefix   = "${var.environment}-todo-api-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type  # t3.small by default

  # Attach the IAM instance profile so EC2 has AWS permissions
  # (read Secrets Manager, pull from ECR, use SSM Session Manager)
  iam_instance_profile {
    name = var.ec2_instance_profile
  }

  # Network config: no public IP — EC2 only reachable via ALB
  network_interfaces {
    associate_public_ip_address = false      # PRIVATE — no internet-facing IP
    security_groups             = [var.app_sg_id]  # only ALB can reach this
    delete_on_termination       = true
  }

  # Encrypt the root EBS volume (disk) using our KMS key.
  # If someone physically removed the disk from an AWS data centre,
  # they could not read the data without the KMS key.
  block_device_mappings {
    device_name = "/dev/xvda"  # root volume
    ebs {
      volume_type           = "gp3" # gp3 = latest generation SSD
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true  # delete disk when instance terminates
    }
  }

  # User data = startup script that runs when the instance boots.
  # base64encode() is required — AWS expects user data in base64 format.
  # The script:
  #   1. Updates the OS packages
  #   2. Installs Java 17
  #   3. Fetches DB and Redis credentials from Secrets Manager
  #   4. Copies the JAR from S3 (or you can pull Docker image from ECR)
  #   5. Starts the Spring Boot API as a background service
  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    environment      = var.environment
    aws_region       = "ap-south-1"
    secrets_arn      = var.secrets_arn
    redis_secret_arn = var.redis_secret_arn
    docdb_endpoint   = var.docdb_endpoint
    redis_endpoint   = var.redis_endpoint
    msk_brokers      = var.msk_brokers
  }))

  # Tag instances created from this template
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.environment}-todo-api"
    }
  }

  # Ensure a new launch template version is created when anything changes
  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Group ─────────────────────────────────────────────
# The ASG uses the Launch Template above to create and manage EC2 instances.
resource "aws_autoscaling_group" "api" {
  name             = "${var.environment}-api-asg"
  desired_capacity = 2   # run 2 instances normally
  min_size         = 2   # never go below 2 (one in each AZ for HA)
  max_size         = 6   # can scale up to 6 during traffic spikes

  # Place instances in PRIVATE subnets — across 2 AZs.
  # ASG automatically distributes instances across the listed subnets.
  # This means if ap-south-1a's data centre has an outage,
  # instances in ap-south-1b keep serving API requests.
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.api.id
    version = "$Latest" # always use the newest version of the template
  }

  # Attach to ALB target group so ALB routes traffic here.
  # ALB health checks the /actuator/health endpoint on each instance.
  # Unhealthy instances are automatically removed from traffic.
  target_group_arns = [var.api_target_group_arn]

  # ELB health check = use ALB's health check (better than EC2 status check)
  # EC2 status = "is the server on?" (not enough)
  # ELB health = "is the application responding on /actuator/health?" (better)
  health_check_type         = "ELB"
  health_check_grace_period = 180  # wait 3 minutes for app to start before checking

  # Instance Refresh: when launch template changes (new app version),
  # replace old instances one at a time without downtime.
  # min_healthy_percentage = 50: keep at least 50% of instances healthy during refresh.
  # With 2 instances: replace one, wait for it to be healthy, then replace the other.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-todo-api"
    propagate_at_launch = true  # add this tag to every instance created by ASG
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# ── CPU-based Auto Scaling Policy ─────────────────────────────────
# When average CPU across all instances exceeds 70%,
# ASG adds more instances until CPU drops below 70%.
# When traffic drops, ASG removes instances down to min_size.
# This is "target tracking" — you set the target (70%) and
# AWS automatically adjusts instance count to meet it.
resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "${var.environment}-api-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.api.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0  # keep average CPU at 70%
  }
}
