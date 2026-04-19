resource "google_service_account" "node" {
  project      = var.project_id
  account_id   = var.node_service_account_id
  display_name = "GKE node service account for ${var.cluster_name}"
}

resource "google_project_iam_member" "node_default_service_account" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  network    = var.network_self_link
  subnetwork = var.subnetwork_self_link

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  # Minimize SSD quota consumed by the temporary default node pool.
  # remove_default_node_pool = true deletes it after cluster creation,
  # but GKE still allocates it briefly. Lowering disk_size_gb here keeps
  # total transient SSD usage within the asia-northeast3 quota limit.
  # 20GB: above the COS image minimum of 12GB, while staying well under the 250GB quota.
  node_config {
    disk_size_gb = 20
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }
}

resource "google_container_node_pool" "primary" {
  project        = var.project_id
  name           = "${var.cluster_name}-node-pool"
  location       = google_container_cluster.primary.location
  cluster        = google_container_cluster.primary.name
  node_count     = var.node_count
  node_locations = var.node_locations

  depends_on = [
    google_project_iam_member.node_default_service_account,
  ]

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    service_account = google_service_account.node.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      role = "primary"
    }
  }
}
