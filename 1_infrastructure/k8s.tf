# google_client_config and kubernetes provider must be explicitly specified like the following.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

resource "kubernetes_namespace" "demo-app" {
  metadata {

    labels = {
      app = var.app_name
    }

    name = var.k8s_namespace
  }
}

resource "kubernetes_service_account" "demo-app" {
  metadata {
    name = var.k8s_service_account
    namespace = kubernetes_namespace.demo-app.metadata.0.name
  }
}
