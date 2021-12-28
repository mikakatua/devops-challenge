# Configure Service Accounts and Identity Federation
locals {
  role_binding = tomap({
    "demo-app" = [ "roles/viewer", "roles/storage.objectViewer" ]
    "github-cicd" = [ "roles/container.admin", "roles/storage.admin", "roles/container.clusterViewer", "roles/artifactregistry.repoAdmin" ]
  })
}

# Workload pool for external identities
resource "google_iam_workload_identity_pool" "demo-pool" {
  provider                  = google-beta
  project                   = var.project_id
  workload_identity_pool_id = "${var.project_id}-pool"
  display_name              = "Demo pool"
}

# GitHub identity provider
resource "google_iam_workload_identity_pool_provider" "github-provider" {
  provider                           = google-beta
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.demo-pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub provider"
  attribute_mapping                  = {
    "google.subject"  = "assertion.sub"
    "attribute.actor" = "assertion.actor"
    "attribute.aud"   = "assertion.aud"
  }
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account for GKE access to GCS
resource "google_service_account" "demo-app-sa" {
  project      = var.project_id
  account_id   = var.app_name
  display_name = "Demo app Service Account"
}

resource "google_project_iam_member" "demo-app-role" {
  count    = length(local.role_binding["demo-app"])
  project  = var.project_id
  role     = local.role_binding["demo-app"][count.index]
  member   = "serviceAccount:${google_service_account.demo-app-sa.email}"
}

# Allow Kubernetes to impersonate the Google service account
resource "google_service_account_iam_binding" "demo-app-iam" {
  service_account_id = google_service_account.demo-app-sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
  ]
}

# Service account for GitHub Actions
resource "google_service_account" "github-sa" {
  project      = var.project_id
  account_id   = "github-cicd"
  display_name = "GitHub Actions Service Account"
}

resource "google_project_iam_member" "github-cicd-role" {
  count    = length(local.role_binding["github-cicd"])
  project  = var.project_id
  role     = local.role_binding["github-cicd"][count.index]
  member   = "serviceAccount:${google_service_account.github-sa.email}"
}

# Allow GitHub Actions to impersonate the Google service account
resource "google_service_account_iam_binding" "github-iam" {
  service_account_id = google_service_account.github-sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.demo-pool.name}/*"
  ]
}

