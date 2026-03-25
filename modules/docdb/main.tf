resource "aws_docdb_subnet_group" "main" {
    name = "${var.env}-docdb-subnet-group"
    subnet_ids = var.data_subnet_ids
    tags = {
        Name = "${var.env}-docdb-subnet-group"
    }
}

resource "aws_docdb_cluster_parameter_group" "main" {
    name = "${var.env}-docdb-params"
    family = "docdb5.0"
    parameter {
        name = "tls"
        value = "enabled"
    }
}

resource "aws_docdb_cluster""main" {
  cluster_identifier      = "${var.env}-docdb"
  engine                  = "docdb"
  master_username         = "admin"
  master_password         = var.docdb_password
  db_subnet_group_name    = aws_docdb_subnet_group.main.name
  vpc_security_group_ids  = [var.db_sg_id]
  storage_encrypted       = true
  kms_key_id              = var.kms_key_arn
  backup_retention_period = 7
  deletion_protection     = true   # prevents accidental deletion
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.main.name
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.env}-docdb-final"
  tags = { Name = "${var.env}-docdb" }
}

resource "aws_docdb_cluster_instance""main" {
  count              = 2
  identifier         = "${var.env}-docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = "db.t3.medium"
}
