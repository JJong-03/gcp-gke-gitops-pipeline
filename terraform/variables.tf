variable "project_id" {
  description = "GCP project ID. Set this through terraform.tfvars or CI variables."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "asia-northeast3"
}

variable "network_name" {
  description = "VPC network name."
  type        = string
  default     = "gke-gitops-vpc"
}

variable "subnet_name" {
  description = "Subnet name for GKE nodes."
  type        = string
  default     = "gke-gitops-subnet"
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR for GKE nodes."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_secondary_range_name" {
  description = "Secondary range name for GKE pods."
  type        = string
  default     = "pods"
}

variable "pods_secondary_cidr" {
  description = "Secondary CIDR range for GKE pods."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_secondary_range_name" {
  description = "Secondary range name for GKE services."
  type        = string
  default     = "services"
}

variable "services_secondary_cidr" {
  description = "Secondary CIDR range for GKE services."
  type        = string
  default     = "10.30.0.0/20"
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "gke-gitops-cluster"
}

variable "gke_node_count" {
  description = "Initial node count per configured node location for the primary node pool."
  type        = number
  default     = 1
}

variable "gke_node_locations" {
  description = "Zones used by the regional GKE node pool."
  type        = list(string)
  default = [
    "asia-northeast3-a",
    "asia-northeast3-c",
  ]
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes."
  type        = string
  default     = "e2-medium"
}

variable "gke_node_disk_size_gb" {
  description = "Boot disk size in GB for GKE nodes. Lower values reduce SSD quota consumption."
  type        = number
  default     = 30
}

variable "gke_node_service_account_id" {
  description = "Service account ID used by GKE nodes for pulling images and node-level Google API access."
  type        = string
  default     = "gke-gitops-node"
}

variable "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID for container images."
  type        = string
  default     = "gke-gitops-images"
}
