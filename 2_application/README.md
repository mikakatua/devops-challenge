# Application deployment
In this folder you will find the steps to deploy the web application to GKE in 2 different ways, using the Bash shell and GitHub Actions

The original application has been improved and the following functionalities have been added:
* Improved logging, providing more details of each web request
* New `/form` handler to process a form submit POST request
* New `/hello` handler that only accepts GET requests
* Default `/` handler that serves a static web site
* Added 2 unit tests executed during the build

## Prerequisites
It is supposed that you have completed the [steps to deploy the infrastructure](../1_infrastructure). Then, you only need:
* The [Docker Engine](https://docs.docker.com/get-docker/) installed
* A [GitHub account](https://github.com/) to be able to run the CI/CD pipeline
* The [GitHub CLI](https://cli.github.com/) installed and configured

## Manual deployment
The following commands deploy the application from a Bash shell. The [CI/CD automated deployment](#cicd-deployment) is preferred, this deployment is provided only for learning purposes, to understand the basic steps to deploy the application

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

This step is only required if you have never pushed an image to GCP Artifact Registry in that region. Then, you have to configure the credential helper to authenticate with the registry
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

Deploy the application and create a service. The static web site will not work with this deployment because we need a custom deployment to mount the bucket into the pods. This will be done later in the CI/CD deployment
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

To test the application we request the endpoint url. To do so, you can add to your `/etc/hosts` file the value of the `EXTERNAL_IP` pointing to the host `app.example.com`. Alternatively, you can use the `Host` request header
```
curl -H "Host: app.example.com" -k https://$EXTERNAL_IP/hello
```

Now, search the Pod logs for the request
```
for pod in $(kubectl get po -n $NAMESPACE -o jsonpath="{.items[*].metadata.name}")
do 
  kubectl logs $pod -n $NAMESPACE | grep /hello
done
```
Note: The logs will show multiple entries because the load balancer periodically performs a health check of the Pods


## CI/CD deployment
In order to run the GitHub Actions workflow, you have to copy the current repository to your GitHub account and configure some settings. The following command creates a fork of the repository in your account
```
gh repo fork mikakatua/devops-challenge --clone=false
# Get the owner of the forked repo
OWNER=$(gh repo view devops-challenge --json owner --jq ".owner.login")
```

We have to create some repository secrets that will be used by the GitHub Actions workflow:
```
# TLS certifcate and key
gh secret set TLS_CRT -R $OWNER/devops-challenge < $APP_NAME.crt
gh secret set TLS_KEY -R $OWNER/devops-challenge < $APP_NAME.key
# Private key for the Terraform service account
cat ~/terraform-automation-key.json | tr -d '\n' | gh secret set TERRAFORM_KEY -R $OWNER/devops-challenge
```
Note: We need remove the new-line chars from the json file to work

Copy the files for the static web site to the GCS bucket
```
BUCKET=$(terraform -chdir=../1_infrastructure output -raw static-web-bucket)
gsutil cp static/* gs://$BUCKET
```

Finally, to run the workflow go to the url https://github.com/OWNER/devops-challenge/actions (replacing *OWNER* with your GitHub user) and enable the workflows. Then, you will be able to run the workflow pushing any change to the `master` branch. Additionally, you can run it from the command line with
```
gh workflow run CI/CD -R $OWNER/devops-challenge
```

There is also a second workflow called "Manual CI/CD". The difference is that this workflow requires some inputs to work and only can be run manually
```
terraform -chdir=../1_infrastructure output -json | \
  jq 'with_entries(.value |= .value)' > cicd_inputs.json
gh workflow run CI/CD -r develop --json < cicd_inputs.json
```

To see the results of the executions you can go to github.com, to the Actions tab, or use the CLI 
```
gh run view -R $OWNER/devops-challenge
```
