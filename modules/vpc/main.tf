# ─────────────────────────────────────────────────────────────────
# modules/vpc/main.tf
#
# PURPOSE: Creates the network inside AWS where all our
# resources will live. Think of this as building the roads,
# walls, and gates of a city before any buildings.
#
# WHAT IT CREATES:
#  - VPC (the city walls)
#  - 6 subnets in 2 AZs (neighbourhoods: public/private/data)
#  - Internet Gateway (the city main gate — allows internet traffic in)
#  - NAT Gateway (one-way gate — private servers go OUT, nothing comes IN)
#  - Route Tables (traffic signs — tells packets where to go)
#  - VPC Flow Logs (CCTV — records all network traffic for auditing)
# ─────────────────────────────────────────────────────────────────

# ── VPC ───────────────────────────────────────────────────────────
# VPC = Virtual Private Cloud.
# It is a private, isolated network inside AWS that belongs only
# to your account. Nothing outside can reach resources inside
# unless you explicitly open it.
# cidr_block = "10.0.0.0/16" means we have 65,536 IP addresses
# available to assign to subnets and resources.
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # enable_dns_hostnames: gives EC2 instances a hostname like
  #   ec2-10-0-3-5.ap-south-1.compute.internal
  # Required for EKS to work properly.
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-vpc"
  }
}

# ── Public Subnets ─────────────────────────────────────────────────
# Public subnets are connected to the internet via the Internet Gateway.
# ONLY the ALB (load balancer) lives here.
# EC2, EKS nodes, and databases NEVER go in public subnets.
#
# count = 2 means Terraform creates 2 identical subnets,
# one in each availability zone (AZ). AZs are separate data centres.
# If AZ ap-south-1a has a power failure, ap-south-1b keeps serving.
#
# The kubernetes.io/role/elb tag tells the AWS Load Balancer
# Controller "you are allowed to create ALBs in these subnets."
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # NEVER auto-assign public IPs — we only want the ALB to have one
  map_public_ip_on_launch = false

  tags = {
    Name                     = "${var.environment}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# ── Private Subnets ────────────────────────────────────────────────
# Private subnets have NO direct internet access.
# EKS worker nodes and EC2 API servers live here.
# They can reach the internet via NAT Gateway (outbound only —
# so they can pull Docker images) but nobody can reach them directly.
#
# The kubernetes.io/role/internal-elb tag tells the AWS Load Balancer
# Controller "you can create internal load balancers here."
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                              = "${var.environment}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ── Data Subnets ──────────────────────────────────────────────────
# Data subnets have ZERO internet access — not even via NAT.
# Only DocumentDB (MongoDB), ElastiCache (Redis), and MSK (Kafka)
# live here. They only need to talk to the app layer, not the internet.
# This is the most isolated layer — maximum security.
resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.environment}-data-${count.index + 1}"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────
# The Internet Gateway (IGW) is the main gate between the VPC
# and the public internet. It only connects to public subnets.
# Without this, even the ALB could not receive traffic from browsers.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-igw"
  }
}

# ── Elastic IP for NAT ─────────────────────────────────────────────
# An Elastic IP is a fixed public IP address.
# The NAT Gateway needs one so that outbound traffic from private
# subnets appears to come from a consistent IP address.
# (Useful for whitelisting your IP with external services.)
resource "aws_eip" "nat" {
  domain = "vpc" # "vpc" is required for EIPs used inside a VPC

  # Make sure the IGW exists before creating the EIP
  depends_on = [aws_internet_gateway.igw]
}

# ── NAT Gateway ───────────────────────────────────────────────────
# NAT = Network Address Translation.
# It sits in a PUBLIC subnet and acts as a one-way door:
#  - Private subnet server → internet: ALLOWED (e.g. pull Docker image)
#  - Internet → private subnet server: BLOCKED
# This is how EC2 and EKS nodes can download packages without
# being directly reachable from the internet.
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # NAT must live in a public subnet

  tags = {
    Name = "${var.environment}-nat"
  }
}

# ── Route Table: Public ───────────────────────────────────────────
# A route table is like a "GPS" for network packets — it says:
# "if the destination is the internet (0.0.0.0/0), go via the IGW."
# This route table is attached to the public subnets.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"              # "all traffic"
    gateway_id = aws_internet_gateway.igw.id # go via internet gateway
  }

  tags = {
    Name = "${var.environment}-public-rt"
  }
}

# ── Route Table: Private ──────────────────────────────────────────
# Private subnets have internet access but only via NAT (outbound only).
# "if destination is internet, go via NAT Gateway (not IGW directly)"
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id # go via NAT, not IGW
  }

  tags = {
    Name = "${var.environment}-private-rt"
  }
}

# ── Route Table: Data ─────────────────────────────────────────────
# Data subnets have NO internet route at all — completely isolated.
# DocumentDB, Redis, and Kafka only need to talk to the app layer
# inside the VPC. They should never reach the internet.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id
  # No routes added — zero internet access

  tags = {
    Name = "${var.environment}-data-rt"
  }
}

# ── Route Table Associations ──────────────────────────────────────
# Associations link each subnet to its route table.
# Without this, subnets would use the VPC default route table.

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count          = 2
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# ── VPC Flow Logs ──────────────────────────────────────────────────
# Flow Logs record EVERY network connection in the VPC:
# who connected to what, from which IP, on which port, accepted or rejected.
# This is used for:
#  - Security auditing (did anything unexpected connect to the DB?)
#  - Debugging (why is traffic being blocked?)
#  - Compliance (some regulations require network logs)
#
# Logs are stored in CloudWatch Logs for querying.
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.environment}"
  retention_in_days = 30 # keep logs for 30 days then auto-delete to save cost
}

# IAM role that allows the VPC Flow Logs service to write to CloudWatch
resource "aws_iam_role" "flow_log_role" {
  name = "${var.environment}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log_policy" {
  name = "flow-log-policy"
  role = aws_iam_role.flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "vpc_flow" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # log both ACCEPTED and REJECTED traffic
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    Name = "${var.environment}-flow-logs"
  }
}
