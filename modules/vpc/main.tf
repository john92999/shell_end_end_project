resource "aws_vpc""main"{
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support = true
    tags = { Name = "${var.env}-vpc" }
}

resource "aws_subnet""public"{
    count = 2
    vpc_id = aws_vpc.main.id
    cidr_block = var.public_cidrs[count.index]
    availability_zone = var.azs[count.index]
    map_public_ip_on_launch = false
    tags = {
        Name = "${var.env}-public-${count.index +1}",
        "kubernetes.io/role/elb" = "1"
    }
}

resource "aws_subnet""private"{
    count = 2
    vpc_id = aws_vpc.main.id
    cidr_block = var.private_cidrs[count.index]
    availability_zone = var.azs[count.index]
    tags = {
        Name = "${var.env}-private-${count.index +1}",
        "kubernetes.io/role/internal-elb" = "1"
    }
}

resource "aws_subnet""data"{
    count = 2
    vpc_id = aws_vpc.main.id
    cidr_block = var.data_cidrs[count.index]
    availability_zone = var.azs[count.index]
    tags = {
        Name = "${var.env}-data-${count.index + 1}"
    }
}

resource "aws_internet_gateway" "igw"{
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "${var.env}-igw"
    }
}

resource "aws_eip" "nat"{
    domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
    allocation_id = aws_eip.nat.id
    subnet_id = aws_subnet.public[0].id
    tags = {
        Name = "${var.env}-nat"
    }
}

resource "aws_route_table""public"{
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "${var.env}-public-rt"
    }
}

resource "aws_route_table""private"{
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.nat.id
    }
    tags = {
        Name = "${var.env}-private-rt"
    }
}

resource "aws_route_table" "data" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "${var.env}-data-rt"
    }
}

resource "aws_route_table_association""public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association""private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association""data" {
  count          = 2
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

resource "aws_flow_log""vpc_flow" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = var.flow_log_role_arn
  log_destination = var.flow_log_group_arn
}
