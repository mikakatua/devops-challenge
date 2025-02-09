# Infrastructure provisioning
This folder contains the instructions to deploy a GKE cluster using Terraform. The gcloud commands are provided but the same can be done from the GCP console

## Architecture
We will create a highly available [regional cluster](https://cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters#regional) with the control plane and nodes replicated across three zones of a region. 

![](https://storage.googleapis.com/gweb-cloudblog-publish/original_images/gcp-google-kubernetes-engine-regional-clusterbcum.PNG)

## Prerequisites
Before trying to provision the infrastructure, you need:
* A [GCP account](https://console.cloud.google.com/) (free-tier is enough)
* The [gcloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured with your GCP account
* The [kubectl CLI](https://kubernetes.io/docs/tasks/tools/) installed
* The [terraform CLI](https://www.terraform.io/downloads) installed

## Create a new project
This is not mandatory but it is good to keep the resources separate
```
gcloud projects create --name=devops-challenge --quiet
```
We save the project ID in a variable for later use
```
PROJECT_ID=$(gcloud projects list --filter="name: devops-challenge" --format="value(projectId)")
```
Before we can create resources, we have to link the project with a billing account. You can do it with the command
```
gcloud beta billing projects link $PROJECT_ID --billing-account=0X0X0X-0X0X0X-0X0X0X
```
Replace `0X0X0X-0X0X0X-0X0X0X` with *your* billing account ID

Finally, we enable the services we need to use with the command
```
gcloud services enable compute.googleapis.com container.googleapis.com cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  --project=$PROJECT_ID
```

## Create the Terraform service account
These commands create the service account and grants the permissions
```
gcloud iam service-accounts create terraform-automation \
  --display-name="Terraform Service Account" \
  --project=$PROJECT_ID

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-automation@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/owner"
```
**Warning**: For the sake of simplicity we granted the `Owner` role to the service account. This role allows create and delete all GCP resources.
From a security perspective, we should enforce the principle of least privilege and grant only the specific roles needed.

Finally, we download the service account private key that will be used later with the Terraform CLI
```
gcloud iam service-accounts keys create ~/terraform-automation-key.json \
  --iam-account="terraform-automation@$PROJECT_ID.iam.gserviceaccount.com"
```

## Create the Terraform backend storage
Create a bucket on Google Cloud Storage (GCS) where Terraform store its state
```
gsutil mb -p $PROJECT_ID -c REGIONAL -l us-east1 -b on gs://devops-challenge-tfstate
```
Feel free to change the region and the bucket name at your convenience

Enable object versioning for the bucket to keep old versions of the state
```
gsutil versioning set on gs://devops-challenge-tfstate
```
Note: It is recommended to set also a lifecycle rule to the bucket to automatically delete old versions

## Provision the infrastructure
Before running the Terraform commands we have to configure the credentials to authenticate with the GCP API. We will specify the service account key file created before using the `GOOGLE_CREDENTIALS` environment variable
```
export GOOGLE_CREDENTIALS=~/terraform-automation-key.json
```

Edit the `terraform.tfvars` and set *your* project ID and the region. Optionally, you can set the environment variables `GOOGLE_PROJECT` and `GOOGLE_REGION`

Run this command to initialize the backend and download the required modules
```
terraform init
```
Run this command to create the resources
```
terraform apply
```

At this point, we have finished creating the infrastructure. We have:
* A GKE cluster to run our Kubernetes workload resources
* A container repository to store the application docker image
* A GCS bucket to store the application static files 
* A Service account for the application to access the bucket
* A Service account for GitHub Actions to deploy Kubernetes resources
* A Kubernetes namespace for the application resources
* A Kubernetes service account for the application

We are ready to continue and [deploy the application](../2_application)

## Clean up the resources
To delete all the provisioned remote objects managed by Terraform, run
```
terraform destroy
```
