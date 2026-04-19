terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "project_services" {
  source = "./modules/project_services"

  project_id = var.project_id
  services   = var.enabled_project_services
}

module "network" {
  source = "./modules/network"

  project_id                    = var.project_id
  region                        = var.region
  network_name                  = var.network_name
  subnet_name                   = var.subnet_name
  subnet_cidr                   = var.subnet_cidr
  pods_secondary_range_name     = var.pods_secondary_range_name
  pods_secondary_cidr           = var.pods_secondary_cidr
  services_secondary_range_name = var.services_secondary_range_name
  services_secondary_cidr       = var.services_secondary_cidr

  depends_on = [
    module.project_services,
  ]
}

module "gke" {
  source = "./modules/gke"

  project_id                    = var.project_id
  region                        = var.region
  cluster_name                  = var.cluster_name
  network_self_link             = module.network.network_self_link
  subnetwork_self_link          = module.network.subnetwork_self_link
  pods_secondary_range_name     = module.network.pods_secondary_range_name
  services_secondary_range_name = module.network.services_secondary_range_name
  node_count                    = var.gke_node_count
  node_locations                = var.gke_node_locations
  machine_type                  = var.gke_machine_type
  disk_size_gb                  = var.gke_node_disk_size_gb
  node_service_account_id       = var.gke_node_service_account_id
}

module "artifact_registry" {
  source = "./modules/artifact_registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = var.artifact_registry_repository_id
  reader_members = {
    gke_node = module.gke.node_service_account_member
  }

  depends_on = [
    module.project_services,
  ]
}

module "github_wif" {
  source = "./modules/github_wif"

  project_id                      = var.project_id
  project_number                  = var.project_number
  region                          = var.region
  artifact_registry_repository_id = module.artifact_registry.repository_id
  github_owner                    = var.github_owner
  github_repository               = var.github_repository
  wif_pool_id                     = var.wif_pool_id
  wif_provider_id                 = var.wif_provider_id
  deploy_service_account_id       = var.github_actions_deploy_service_account_id

  depends_on = [
    module.project_services,
  ]
}
