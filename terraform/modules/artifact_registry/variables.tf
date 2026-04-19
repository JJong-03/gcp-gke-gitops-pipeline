variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Artifact Registry location."
  type        = string
}

variable "repository_id" {
  description = "Artifact Registry repository ID."
  type        = string
}

variable "reader_members" {
  description = "Map of static keys to IAM member strings for repository-scoped Artifact Registry reader access."
  type        = map(string)
  default     = {}
}
