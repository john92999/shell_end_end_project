# ─────────────────────────────────────────────────────────────────
# modules/msk/main.tf
#
# PURPOSE: Creates Amazon MSK — the Kafka message queue.
#
# WHAT IS KAFKA / MSK?
#   Kafka is a message queue — a service that lets parts of your
#   application communicate asynchronously.
#
#   WITHOUT Kafka (synchronous):
#     User creates todo → API saves to DB → waits for response
#     If DB is slow → user waits → bad experience
#     If you need to send an email notification → user waits more
#
#   WITH Kafka (asynchronous):
#     User creates todo → API saves to DB → immediately responds "done!"
#     API ALSO publishes a message to Kafka: "todo-created event"
#     A separate "consumer" service reads from Kafka and:
#       - Sends email notification
#       - Updates analytics
#       - Syncs to other systems
#     User never waits for these — they happen in background.
#
#   MSK = AWS's managed Kafka. AWS manages the servers, patches,
#   and availability. You just produce and consume messages.
#
# WHY 3 BROKERS (not 2 like the original code)?
#   Kafka replicates messages across brokers for reliability.
#   Kafka requires a majority (quorum) to confirm a write.
#   With 2 brokers: if 1 fails → no majority → Kafka stops working
#   With 3 brokers: if 1 fails → 2 remaining = majority → keeps working
#   3 brokers is the MINIMUM for production. Original code had 2 — wrong.
#   We put one broker in each of the 3 subnets (1 per AZ).
#
# NOTE: We use 3 data subnets here but the vpc module only creates 2.
# For MSK, you need exactly broker_count subnets (one per broker).
# We'll use the 2 data subnets and set broker count to 2 for dev,
# noting that 3 is needed for production with 3 AZs.
# ─────────────────────────────────────────────────────────────────

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.environment}-todo-msk"
  kafka_version          = "3.5.1" # Kafka version 3.5.1 — latest stable
  number_of_broker_nodes = 2       # 2 for dev (matches 2 subnets); use 3 for production

  broker_node_group_info {
    # kafka.t3.small: small instance suitable for dev/test
    # Use kafka.m5.large for production workloads
    instance_type = "kafka.t3.small"

    # Subnets where brokers are placed — one broker per subnet.
    # Each subnet is in a different AZ, so each broker is in a
    # different data centre. If one AZ fails, other brokers serve.
    client_subnets = var.data_subnet_ids

    # Only app layer can connect to Kafka (ports 9092-9094)
    security_groups = [var.msk_sg_id]

    storage_info {
      ebs_storage_info {
        # 20 GB per broker for storing messages.
        # Kafka deletes old messages after retention period.
        # Increase this if you expect high message volume.
        volume_size = 20
      }
    }
  }

  # Encryption configuration — protects Kafka messages
  encryption_info {
    # Encrypt messages stored on broker disks using our KMS key
    encryption_at_rest_kms_key_arn = var.kms_key_arn

    encryption_in_transit {
      # client_broker: encryption between your app and Kafka brokers
      # "TLS" means all connections MUST use TLS — no plaintext allowed
      client_broker = "TLS"

      # in_cluster: encryption between brokers themselves
      # (when a broker replicates a message to another broker)
      in_cluster = true
    }
  }

  # Open monitoring allows Prometheus to scrape Kafka metrics.
  # jmx_exporter: exposes Kafka broker metrics (messages/sec, lag, etc.)
  # node_exporter: exposes EC2 node metrics for Kafka broker servers
  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  # Broker logs: send Kafka logs to CloudWatch so you can debug issues
  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = "/aws/msk/${var.environment}-todo"
      }
    }
  }

  tags = {
    Name = "${var.environment}-msk"
  }
}

# CloudWatch Log Group for MSK broker logs
resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.environment}-todo"
  retention_in_days = 7 # keep MSK logs for 7 days

  tags = {
    Name = "${var.environment}-msk-logs"
  }
}
