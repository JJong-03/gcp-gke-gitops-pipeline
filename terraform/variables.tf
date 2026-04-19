variable "project_id" {
  description = "GCP project ID. Set this through terraform.tfvars or CI variables."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "asia-northeast3"
}

variable "project_number" {
  description = "Numeric GCP project number. Required for Workload Identity Federation principal identifiers."
  type        = string
}

variable "enabled_project_services" {
  description = "GCP APIs managed by Terraform for this project."
  type        = set(string)
  default = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ]
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

variable "github_owner" {
  description = "GitHub repository owner or organization used by the Workload Identity Provider condition."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name used by the Workload Identity Provider condition."
  type        = string
}

variable "wif_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions."
  type        = string
  default     = "github-actions"
}

variable "wif_provider_id" {
  description = "Workload Identity Pool Provider ID for this repository."
  type        = string
  default     = "gke-gitops-pipeline"
}

variable "github_actions_deploy_service_account_id" {
  description = "Service account ID used by GitHub Actions for Artifact Registry pushes."
  type        = string
  default     = "github-actions-deploy"
}
