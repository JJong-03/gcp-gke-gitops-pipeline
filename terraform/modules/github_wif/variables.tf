variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "project_number" {
  description = "Numeric GCP project number used in Workload Identity principal identifiers."
  type        = string
}

variable "region" {
  description = "Artifact Registry repository location."
  type        = string
}

variable "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID that GitHub Actions can push to."
  type        = string
}

variable "github_owner" {
  description = "GitHub repository owner or organization used by the OIDC provider condition."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name used by the OIDC provider condition."
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

variable "deploy_service_account_id" {
  description = "Service account ID used by GitHub Actions for Artifact Registry pushes."
  type        = string
  default     = "github-actions-deploy"
}
