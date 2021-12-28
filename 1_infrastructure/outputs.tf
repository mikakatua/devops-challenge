output "project_id" {
  value = var.project_id
}

output "region" {
  value = module.gke.region
}

output "cluster_name" {
  description = "Cluster name"
  value       = module.gke.name
}

output "kubernetes_endpoint" {
  sensitive = true
  value = module.gke.endpoint
}

output "master_kubernetes_version" {
  description = "The master Kubernetes version"
  value       = module.gke.master_version
}

output "repository_name" {
  description = "Artifact Registry repository"
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.my-repo.repository_id}" 
}

output "github_identity_provider" {
  description = "GitHub identity"
  value = google_iam_workload_identity_pool_provider.github-provider.name
}

output "k8s_namespace" {
  description = "Kubernetes namespace"
  value = kubernetes_namespace.demo-app.metadata.0.name
}

output "k8s_service_account" {
  description = "Kubernetes service account"
  value = data.kubernetes_service_account.demo-app.metadata
}
