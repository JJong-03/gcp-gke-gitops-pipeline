resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker image repository for the GKE GitOps portfolio pipeline"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = var.reader_members

  project    = var.project_id
  location   = google_artifact_registry_repository.docker.location
  repository = google_artifact_registry_repository.docker.repository_id
  role       = "roles/artifactregistry.reader"
  member     = each.value
}
