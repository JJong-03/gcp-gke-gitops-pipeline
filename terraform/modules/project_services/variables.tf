variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "services" {
  description = "Set of GCP APIs to enable and keep enabled for this project."
  type        = set(string)
}
