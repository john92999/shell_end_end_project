resource "aws_msk_cluster""main" {
  cluster_name           = "${var.env}-msk"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 3    # MUST be 3 — one per AZ

  broker_node_group_info {
    instance_type  = "kafka.t3.small"
    client_subnets = var.data_subnet_ids    # 3 subnets, one per AZ
    security_groups = [var.msk_sg_id]
    storage_info {
      ebs_storage_info { volume_size = 100 }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"      # force TLS between clients and brokers
      in_cluster    = true       # TLS between brokers
    }
    encryption_at_rest_kms_key_arn = var.kms_key_arn
  }

  # Enable monitoring for Prometheus
  open_monitoring {
    prometheus {
      jmx_exporter  { enabled_in_broker = true }
      node_exporter { enabled_in_broker = true }
    }
  }

  tags = { Name = "${var.env}-msk" }
}
