output "enabled_services" {
  description = "GCP APIs represented by this module."
  value       = keys(google_project_service.services)
}
