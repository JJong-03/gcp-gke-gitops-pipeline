output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "VPC network self link."
  value       = google_compute_network.vpc.self_link
}

output "subnetwork_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.gke.name
}

output "subnetwork_self_link" {
  description = "Subnet self link."
  value       = google_compute_subnetwork.gke.self_link
}

output "pods_secondary_range_name" {
  description = "Secondary range name for pods."
  value       = var.pods_secondary_range_name
}

output "services_secondary_range_name" {
  description = "Secondary range name for services."
  value       = var.services_secondary_range_name
}
