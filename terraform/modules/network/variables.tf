variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the subnet."
  type        = string
}

variable "network_name" {
  description = "VPC network name."
  type        = string
}

variable "subnet_name" {
  description = "Subnet name."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR."
  type        = string
}

variable "pods_secondary_range_name" {
  description = "Secondary range name for GKE pods."
  type        = string
}

variable "pods_secondary_cidr" {
  description = "Secondary CIDR range for GKE pods."
  type        = string
}

variable "services_secondary_range_name" {
  description = "Secondary range name for GKE services."
  type        = string
}

variable "services_secondary_cidr" {
  description = "Secondary CIDR range for GKE services."
  type        = string
}
