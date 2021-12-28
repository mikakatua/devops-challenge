# Warning: Variables may not be used here.
terraform {
  backend "gcs" {
    bucket      = "devops-challenge-tfstate"
    prefix      = "terraform/state"
  }
}
