resource "google_storage_bucket" "demo-bucket" {
  name     = "${var.project_id}-${var.app_name}-static"
  project  = var.project_id
  location = var.region
}

resource "google_storage_bucket_iam_binding" "binding" {
  bucket = google_storage_bucket.demo-bucket.name
  role = "roles/storage.objectViewer"
  members = [
    "serviceAccount:${google_service_account.demo-app-sa.email}"
  ]
}
