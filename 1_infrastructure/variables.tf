variable "project_id" {
  description = "The project ID to host the cluster in"
}

variable "region" {
  description = "The region to host the cluster in"
}

variable "network" {
  description = "The VPC network to host the cluster in"
  default = "gke-vpc"
}

variable "subnetwork" {
  description = "The subnetwork to host the cluster in"
  default = "gke-subnet"
}

variable "ip_range_pods" {
  description = "The secondary ip range to use for pods"
  default = "gke-pods-subnet"
}

variable "ip_range_services" {
  description = "The secondary ip range to use for services"
  default = "gke-services-subnet"
}

variable "app_name" {
  description = "The application name"
  default = "demo-app"
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for the applicaiton"
  default = "demo-app"
}

variable "k8s_service_account" {
  description = "Kubernetes service account for the applicaiton"
  default = "demo-app"
}

