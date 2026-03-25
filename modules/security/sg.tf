resource "aws_security_group" "alb_sg" {
    name = "${var.env}-alb-sg"
    vpc_id = var.vpc_id
    ingress {
        from_port = 80
        to_port = 80
        protocol = tcp
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = tcp
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "${var.env}-alb-sg"
    }
}

resource "aws_security_group" "app_sg" {
    name = "${var.env}-app-sg"
    vpc_id = var.vpc_id
    ingress {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        security_groups = [aws_security_group.alb_sg.id]
    }
        egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "${var.env}-app-sg"
    }
}

resource "aws_security_group" "db_sg"{
    name   = "${var.env}-db-sg"
    vpc_id = var.vpc_id
    ingress {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        security_groups = [aws_security_group.app_sg.id]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "${var.env}-db-sg"
    }
}

resource "aws_security_group" "redis_sg"{
    name   = "${var.env}-redis-sg"
    vpc_id = var.vpc_id
    ingress {
        from_port = 6379
        to_port = 6379
        protocol = "tcp"
        security_groups = [aws_security_group.app_sg.id]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "${var.env}-redis-sg"
    }
}

resource "aws_security_group" "msk_sg"{
    name   = "${var.env}-msk-sg"
    vpc_id = var.vpc_id
    ingress {
        from_port = 9092
        to_port = 9094
        protocol = "tcp"
        security_groups = [aws_security_group.app_sg.id]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "${var.env}-msk-sg"
    }
}


