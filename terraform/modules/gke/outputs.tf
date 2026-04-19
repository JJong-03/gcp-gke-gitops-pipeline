output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.primary.name
}

output "location" {
  description = "GKE cluster location."
  value       = google_container_cluster.primary.location
}

output "endpoint" {
  description = "GKE cluster endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "node_pool_name" {
  description = "Primary node pool name."
  value       = google_container_node_pool.primary.name
}

output "node_service_account_email" {
  description = "Service account used by GKE nodes."
  value       = google_service_account.node.email
}

output "node_service_account_member" {
  description = "IAM member string for the GKE node service account."
  value       = google_service_account.node.member
}
