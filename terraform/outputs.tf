output "network_name" {
  description = "Created VPC network name."
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Created subnet name."
  value       = module.network.subnetwork_name
}

output "gke_cluster_name" {
  description = "Created GKE cluster name."
  value       = module.gke.cluster_name
}

output "gke_cluster_location" {
  description = "GKE cluster location."
  value       = module.gke.location
}

output "gke_node_service_account_email" {
  description = "Service account used by GKE nodes."
  value       = module.gke.node_service_account_email
}

output "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID."
  value       = module.artifact_registry.repository_id
}
