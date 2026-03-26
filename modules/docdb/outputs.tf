# modules/docdb/outputs.tf

output "cluster_endpoint" {
  description = "The connection endpoint for DocumentDB. Your app connects here for writes."
  value       = aws_docdb_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "The read-only endpoint. Use for read-heavy queries to spread load."
  value       = aws_docdb_cluster.main.reader_endpoint
}

output "cluster_port" {
  description = "DocumentDB port (27017 — same as MongoDB)"
  value       = aws_docdb_cluster.main.port
}
