variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GKE cluster region."
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
}

variable "network_self_link" {
  description = "VPC network self link."
  type        = string
}

variable "subnetwork_self_link" {
  description = "Subnet self link."
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Secondary range name for GKE pods."
  type        = string
}

variable "services_secondary_range_name" {
  description = "Secondary range name for GKE services."
  type        = string
}

variable "node_count" {
  description = "Node count per configured node location for the primary node pool."
  type        = number
}

variable "node_locations" {
  description = "Zones used by the regional GKE node pool."
  type        = list(string)
}

variable "machine_type" {
  description = "Machine type for GKE nodes."
  type        = string
}

variable "node_service_account_id" {
  description = "Service account ID used by GKE nodes."
  type        = string
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for GKE nodes. Lower values reduce SSD quota consumption."
  type        = number
  default     = 30
}
