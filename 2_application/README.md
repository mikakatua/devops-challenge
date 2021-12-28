# Application deployment
In this folder you will find the steps to deploy the web application to GKE in 2 different ways, using the Bash shell and GitHub Actions

The original application has been improved and the following funcionalities have been added:
* Improved logging, providing more details of each web request
* New /form handler to process a form submit POST request
* New /hello handler that only accepts GET requests
* Default / handler that serves a stating web site
* Added 2 unit tests executed during the build

## Prerequisites
It is supposed that you have completed the [steps to deploy the infrastructure](../1_infrastructure). Then, you only need:
* The [Docker Engine](https://docs.docker.com/get-docker/) installed
* The [GitHub CLI](https://cli.github.com/) installed and configured

## Manual deployment
The following commands deploy the application from a Bash shell. The CI/CD automated deployment is preferred, this deployment is provided only for learning purposes, to understand the basic steps to deploy the application.

### Build and push
We build the image of the application locally and push it to the Artifact Registry in Google Cloud
```
# Get some variables from Terraform state
APP_NAME=$(terraform -chdir=../1_infrastructure output -raw k8s_application)
REGION=$(terraform -chdir=../1_infrastructure output -raw region)
IMAGE=$(terraform -chdir=../1_infrastructure output -raw repository_name)/$APP_NAME:v1
# Create the container image
docker build -f Dockerfile -t $IMAGE .
```

This step is only requred if you have never pushed an image to GCP Artifact Registry in that region. Then, you have to configure the credential helper to authenticate with the registry
```
gcloud --quiet auth configure-docker $REGION-docker.pkg.dev
```

Finally, push the image to the repository
```
docker push $IMAGE
```

### Kubernetes deployment
The following steps deploy the application and make it reachable from Internet using HTTPS. For this example we only use the `kubectl` tool to create the resources instead of using YALM manifests.

Before we start, we need to fetch the Kubernetes credentials to use with kubectl
```
CLUSTER_NAME=$(terraform -chdir=../1_infrastructure output -raw cluster_name)
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION \
  --project=$PROJECT_ID
```
By default, credentials are written to `~/.kube/config`. You can provide an alternate path by setting the `KUBECONFIG` environment variable.

```
# Create the deployment and the service
NAMESPACE=$(terraform -chdir=../1_infrastructure output -raw k8s_namespace)
kubectl create deployment $APP_NAME -n $NAMESPACE --image=$IMAGE --replicas=3
kubectl expose deployment $APP_NAME -n $NAMESPACE --name=${APP_NAME}-svc \
  --type=ClusterIP --port 8080 --target-port 8080
# Check that application Pods are running
kubectl get po -n $NAMESPACE -o wide -l app=$APP_NAME
```
We have created a service of type `ClusterIP` to use [container-native load balancing](https://cloud.google.com/kubernetes-engine/docs/concepts/container-native-load-balancing)

Create a self-signed TLS certificate, using OpenSSL, to serve HTTPS requests
```
openssl req -x509 -newkey rsa:2048 -keyout $APP_NAME.key -out $APP_NAME.crt \
  -subj "/CN=app.example.com/O=Example" -days 365 -nodes

# Create a secret to allow Kubernetes use the TLS certificate
kubectl create secret tls -n $NAMESPACE ${APP_NAME}-secret \
  --key $APP_NAME.key --cert $APP_NAME.crt
```
Note: This certificate is generated for a fake host name `app.example.com`

We want to use the Ingress feature to redirect HTTP traffic to HTTPS. The `FrontendConfig` custom resource definition (CRD) allows us to further customize the load balancer
```
cat <<! | kubectl apply -f -
apiVersion: networking.gke.io/v1beta1
kind: FrontendConfig
metadata:
  name: http-to-https
  namespace: $NAMESPACE
spec:
  redirectToHttps:
    enabled: true
    responseCodeName: MOVED_PERMANENTLY_DEFAULT
!
```

Finally, create the Ingress resource specifying the service as a backend and the secret containing the TLS certificate
```
kubectl create ingress ${APP_NAME}-ing -n $NAMESPACE \
  --annotation=kubernetes.io/ingress.class=gce \
  --annotation=networking.gke.io/v1beta1.FrontendConfig=http-to-https \
  --rule="app.example.com/*=${APP_NAME}-svc:8080,tls=${APP_NAME}-secret"
```

This Ingress automatically deploys an external load balancer in GCP and it will take some minutes to be available. Once the Ingress is ready, we can get the load balancer external IP address
```
EXTERNAL_IP=$(kubectl get ing ${APP_NAME}-ing -n $NAMESPACE -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
```

We can check the health status of the Pod backends with the command
```
gcloud compute backend-services get-health "$(gcloud compute backend-services list --project $PROJECT_ID \
  --filter="name~$APP_NAME" --format="value(name)")" --global --project $PROJECT_ID
```

To test the application we can request the endpoint url and search the Pod logs
```
curl -H "Host: app.example.com" -k https://$EXTERNAL_IP/hello

for pod in $(kubectl get po -n $NAMESPACE -o jsonpath="{.items[*].metadata.name}")
do 
  kubectl logs $pod -n $NAMESPACE | grep /hello
done
```

Note: The logs will show multiple entries because the load balancer periodically performs a health check of the Pods

## CI/CD deployment
Create a GCP service account to grant the CI/CD pipeline access to GKE
```
gcloud iam service-accounts create github-cicd \
  --display-name="GitHub Service Account" \
  --project=$PROJECT_ID

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-cicd@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-cicd@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-cicd@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.clusterViewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:github-cicd@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.repoAdmin"

gcloud iam service-accounts keys create ~/github-cicd-key.json \
  --iam-account="github-cicd@$PROJECT_ID.iam.gserviceaccount.com"

gh secret set GCP_PROJECT_ID -b $PROJECT_ID
gh secret set GCP_SA_KEY < ~/github-cicd-key.json
```

Setting up Workload Identity Federation for GitHub Actions
```
gcloud iam workload-identity-pools create "devops-challenge-pool" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="Demo pool"

WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools list --location=global --filter="name: devops-challenge" --format="value(name)")

gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="devops-challenge-pool" \
  --display-name="GitHub provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=assertion.aud" \
  --issuer-uri="https://token.actions.githubusercontent.com"

WORKLOAD_IDENTITY_PROVIDER_ID=$(gcloud iam workload-identity-pools providers list --workload-identity-pool=$WORKLOAD_IDENTITY_POOL_ID --location=global --filter="name: devops-challenge" --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "github-cicd@${PROJECT_ID}.iam.gserviceaccount.com" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/*" \
  --role="roles/iam.workloadIdentityUser"
```

