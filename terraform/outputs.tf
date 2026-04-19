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

output "enabled_project_services" {
  description = "GCP APIs represented in Terraform."
  value       = module.project_services.enabled_services
}

output "github_actions_deploy_service_account_email" {
  description = "Service account used by GitHub Actions for Artifact Registry pushes."
  value       = module.github_wif.deploy_service_account_email
}

output "github_actions_workload_identity_provider" {
  description = "Workload Identity Provider resource name for GitHub Actions authentication."
  value       = module.github_wif.workload_identity_provider
}
