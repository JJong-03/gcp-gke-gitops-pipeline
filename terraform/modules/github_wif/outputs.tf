output "deploy_service_account_email" {
  description = "Email of the GitHub Actions deploy service account."
  value       = google_service_account.deploy.email
}

output "deploy_service_account_member" {
  description = "IAM member string for the GitHub Actions deploy service account."
  value       = google_service_account.deploy.member
}

output "workload_identity_provider" {
  description = "Workload Identity Provider resource name for GitHub Actions authentication."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "repository_principal" {
  description = "Repository-scoped Workload Identity principal bound to the deploy service account."
  value       = local.github_repository_principal
}
