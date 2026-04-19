# Reproduction Runbook

이 문서는 이 저장소를 처음부터 다시 따라 실행하기 위한 절차형 runbook이다.

세부 설계 이유는 각 주제별 문서에 남기고, 여기서는 실행 순서와 확인 지점만 다룬다. 실제 계정별 값은 placeholder로 표기하며, secret/token/credential 값은 문서에 기록하지 않는다.

## 0. What This Runbook Does

이 runbook을 따르면 다음 흐름을 재현할 수 있다.

```text
Terraform
  -> GCP APIs
  -> VPC/Subnet
  -> Artifact Registry
  -> GKE regional cluster and node pool
  -> GKE node IAM
  -> GitHub Actions deploy service account and WIF

GitHub Actions
  -> Docker image build
  -> Artifact Registry push

Argo CD
  -> syncs k8s/ desired state to GKE
  -> exposes sample app through GKE Ingress
```

Argo CD 설치는 Terraform 범위가 아니며, 이 문서에서는 별도 bootstrap 단계로 다룬다.

## 1. Prerequisites

로컬에 아래 기본 도구가 필요하다.

```bash
gcloud --version
terraform version
kubectl version --client
gke-gcloud-auth-plugin --version
git --version
```

아래 도구는 선택 단계에서만 필요하다.

```bash
docker version
gh --version
```

`docker`는 로컬 image build/push smoke test를 할 때만 필요하다. GitHub Actions만으로 image push를 검증한다면 생략할 수 있다. `gh`는 GitHub repository variables/secrets를 CLI로 설정할 때만 필요하다. GitHub 웹 UI로 설정한다면 생략할 수 있다.

필요하면 GKE 도구를 설치한다.

```bash
gcloud components install kubectl gke-gcloud-auth-plugin
```

패키지 설치형 Google Cloud CLI에서는 아래가 필요할 수 있다.

```bash
sudo apt-get update
sudo apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin
```

이 문서의 명령은 repository root에서 실행하는 것을 기준으로 한다. `terraform/`으로 이동하지 않고 모든 Terraform 명령은 `terraform -chdir=terraform ...` 형태로 실행한다.

```bash
git rev-parse --show-toplevel
```

GCP project는 미리 생성되어 있어야 하며 billing이 연결되어 있어야 한다. billing 상태 확인 명령은 gcloud 인증과 `PROJECT_ID` 설정 후 3단계에서 실행한다.

Terraform 실행 계정에는 GCP API enablement, IAM, VPC/Subnet, GKE, Artifact Registry, Workload Identity Federation을 만들 수 있는 권한이 필요하다. 개인 검증용 새 project에서는 project `Owner`가 가장 단순하다. 최소 권한으로 나누려면 아래 역할에 해당하는 권한이 필요하다.

- Service Usage Admin
- Compute Network Admin
- Kubernetes Engine Admin
- Artifact Registry Admin
- Service Account Admin
- Workload Identity Pool Admin
- Project IAM Admin

## 2. Set Local Variables

실제 값은 local shell이나 `terraform/terraform.tfvars`에만 둔다.

```bash
export PROJECT_ID="YOUR_GCP_PROJECT_ID"
export REGION="asia-northeast3"
export CLUSTER_NAME="gke-gitops-cluster"
export AR_REPOSITORY="gke-gitops-images"
export GITHUB_OWNER="YOUR_GITHUB_OWNER"
export GITHUB_REPOSITORY="gcp-gke-gitops-pipeline"
export GITHUB_REPO="${GITHUB_OWNER}/${GITHUB_REPOSITORY}"
```

`GITHUB_OWNER`와 `GITHUB_REPOSITORY`는 Terraform의 WIF repository condition에 들어가므로 실제 GitHub repository 이름과 일치해야 한다.

## 3. Authenticate To GCP

로컬 gcloud 계정과 Application Default Credentials를 준비한다.

```bash
gcloud auth login
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"
gcloud auth application-default login
```

현재 계정과 project를 확인한다.

```bash
gcloud auth list
gcloud config list
```

Billing 연결 상태를 확인한다.

```bash
gcloud billing projects describe "${PROJECT_ID}" \
  --format="value(billingEnabled)"
```

기대 결과는 `True`다. 조직 정책이나 권한 때문에 billing 상태를 조회할 수 없다면 GCP Console에서 billing 연결을 먼저 확인한다.

Project number를 확인하고 shell 변수에 저장한다.

```bash
export PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" \
  --format="value(projectNumber)")"
echo "${PROJECT_NUMBER}"
```

기대 결과는 숫자로만 된 project number다. project ID와 project number는 다르며, WIF principal identifier에는 project number가 필요하다.

완전히 새 project에서는 Terraform이 API를 관리하기 전에 Service Usage API bootstrap이 필요할 수 있다. Terraform plan/apply에서 API enablement 호출이 실패하면 아래 명령을 먼저 실행한다.

```bash
gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com \
  --project "${PROJECT_ID}"
```

bootstrap API 상태를 확인한다.

```bash
gcloud services list \
  --enabled \
  --project "${PROJECT_ID}" \
  --filter="name:(serviceusage.googleapis.com OR cloudresourcemanager.googleapis.com)"
```

## 4. Prepare Terraform Variables

예시 파일을 복사한다.

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`terraform/terraform.tfvars`에서 최소 아래 값을 실제 값으로 바꾼다.

```hcl
project_id        = "YOUR_GCP_PROJECT_ID"
project_number    = "YOUR_GCP_PROJECT_NUMBER"
region            = "asia-northeast3"
github_owner      = "YOUR_GITHUB_OWNER"
github_repository = "gcp-gke-gitops-pipeline"
```

`project_number`에는 위에서 확인한 숫자 project number를 넣는다. project ID를 넣으면 WIF principal이 잘못 만들어진다.

`terraform.tfvars`는 `.gitignore` 대상이므로 커밋하지 않는다.

## 5. Provision GCP Infrastructure

Terraform을 초기화하고 계획을 확인한다.

```bash
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

계획에 예상하지 않은 destroy/recreate가 없는지 확인한 뒤 apply한다.

```bash
terraform -chdir=terraform apply
```

주요 output을 확인한다.

```bash
terraform -chdir=terraform output
terraform -chdir=terraform output -raw github_actions_workload_identity_provider
terraform -chdir=terraform output -raw github_actions_deploy_service_account_email
terraform -chdir=terraform output -raw gke_node_service_account_email
```

이 단계가 생성/관리하는 주요 리소스:

- GCP API enablement
- VPC/Subnet and secondary IP ranges
- Artifact Registry repository
- GKE regional cluster and node pool
- GKE node service account and image pull IAM
- GitHub Actions deploy service account
- Workload Identity Pool/Provider
- repository-scoped `roles/iam.workloadIdentityUser`
- Artifact Registry writer IAM for GitHub Actions deploy service account

## 6. Configure GitHub Repository Settings

GitHub 웹 UI로 설정할 수 있다.

```text
Repository -> Settings -> Secrets and variables -> Actions
```

GitHub repository variables를 설정한다.

| Variable | Value |
|---|---|
| `GCP_PROJECT_ID` | `YOUR_GCP_PROJECT_ID` |
| `GCP_REGION` | `asia-northeast3` |
| `ARTIFACT_REGISTRY_REPOSITORY` | `gke-gitops-images` |

GitHub repository secrets를 설정한다.

| Secret | Value source |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `terraform -chdir=terraform output -raw github_actions_workload_identity_provider` |
| `GCP_SERVICE_ACCOUNT` | `terraform -chdir=terraform output -raw github_actions_deploy_service_account_email` |

Secret 값은 repository 파일이나 문서에 기록하지 않는다.

GitHub CLI를 사용하는 경우 대상 repository를 명시하고, secret 값은 직접 치지 말고 Terraform output에서 전달한다.

```bash
gh auth status
gh repo view "${GITHUB_REPO}"

gh variable set GCP_PROJECT_ID \
  --repo "${GITHUB_REPO}" \
  --body "${PROJECT_ID}"
gh variable set GCP_REGION \
  --repo "${GITHUB_REPO}" \
  --body "${REGION}"
gh variable set ARTIFACT_REGISTRY_REPOSITORY \
  --repo "${GITHUB_REPO}" \
  --body "${AR_REPOSITORY}"

gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER \
  --repo "${GITHUB_REPO}" \
  --body "$(terraform -chdir=terraform output -raw github_actions_workload_identity_provider)"
gh secret set GCP_SERVICE_ACCOUNT \
  --repo "${GITHUB_REPO}" \
  --body "$(terraform -chdir=terraform output -raw github_actions_deploy_service_account_email)"
```

설정 후 GitHub UI에서 variable/secret 이름만 확인한다. secret 값 자체를 화면 캡처하거나 문서에 붙여 넣지 않는다.

## 7. Validate GKE Access

GKE credentials를 가져온다.

```bash
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"
```

기본 상태를 확인한다.

```bash
kubectl get nodes
kubectl get pods -A
```

기대 결과:

- node 2개가 `Ready`
- GKE system pods가 `Running` 또는 정상 상태

## 8. Build And Push A Test Image

GitHub Actions 검증 전에 로컬 smoke test를 원하면 Docker image를 수동으로 push할 수 있다.

```bash
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}/sample-app:manual-$(date +%Y%m%d%H%M%S)"
gcloud auth configure-docker "${REGION}-docker.pkg.dev"
docker build -t "${IMAGE}" ./app
docker push "${IMAGE}"
echo "${IMAGE}"
```

이 단계는 선택이다. Docker가 없거나 GitHub Actions WIF 검증만으로 image push 흐름을 확인하려면 8-10단계를 건너뛰고 11단계로 이동한다.

## 9. Deploy Sample App Manually

공개 repository의 `k8s/deployment.yaml`은 placeholder image를 유지한다. 수동 배포 검증에서는 repository 파일을 직접 수정하지 않고 임시 manifest를 만들어 적용한다.

```bash
grep -n "image:" k8s/deployment.yaml
```

8단계에서 만든 `IMAGE` 값이 남아 있는지 확인한다.

```bash
echo "${IMAGE:?Set IMAGE to an Artifact Registry sample-app image URI first}"
```

임시 manifest를 만들고 image만 실제 값으로 바꿔 적용한다.

```bash
MANUAL_DEPLOYMENT="$(mktemp /tmp/sample-app-deployment.XXXXXX.yaml)"
cp k8s/deployment.yaml "${MANUAL_DEPLOYMENT}"
sed -i "s#^          image: .*#          image: \"${IMAGE}\"#" "${MANUAL_DEPLOYMENT}"
grep -n "image:" "${MANUAL_DEPLOYMENT}"

kubectl apply -f "${MANUAL_DEPLOYMENT}"
kubectl rollout status deployment/sample-app
kubectl get deploy,pods
kubectl describe pod -l app=sample-app
```

기대 결과:

- Deployment `READY`가 `2/2`
- Pods `Running`
- Pod events에 `Successfully pulled image`

repository 파일이 바뀌지 않았는지 확인한다.

```bash
git status --short
```

## 10. Apply Service And Ingress

```bash
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

상태를 확인한다.

```bash
kubectl get svc sample-app
kubectl describe svc sample-app
kubectl get ingress sample-app
kubectl describe ingress sample-app
```

기대 결과:

- Service type `ClusterIP`
- Service에 GKE NEG annotation/status 확인
- Ingress class는 GCE
- Ingress address가 할당됨
- backend가 sample app endpoints로 연결됨

External IP가 할당될 때까지 시간이 걸릴 수 있다.

```bash
kubectl get ingress sample-app -w
```

HTTP 응답을 확인한다.

```bash
INGRESS_IP="$(kubectl get ingress sample-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
curl -i "http://${INGRESS_IP}/"
```

기대 결과:

```text
HTTP/1.1 200 OK
```

## 11. Validate GitHub Actions CI

`main` branch에 push하면 GitHub Actions가 image를 build/push한다. 검증만 필요하면 빈 커밋으로 트리거해도 된다.

```bash
git status --short
git branch --show-current
git commit --allow-empty -m "Trigger CI image push validation"
git push
CI_TAG="$(git rev-parse HEAD)"
echo "${CI_TAG}"
```

이 검증에서는 `git add .`를 사용하지 않는다. 빈 커밋은 local file 변경을 stage하지 않으므로, 의도하지 않은 파일이 함께 커밋되는 것을 피할 수 있다. `git status --short`에 예상하지 못한 변경이 보이면 먼저 정리하거나 별도 branch에서 진행한다.

GitHub Actions run에서 다음을 확인한다.

- `Build image` job 성공
- `Push image` job 성공
- Artifact Registry에 commit SHA tag 생성

Artifact Registry에서 image를 확인한다.

```bash
gcloud artifacts docker images list \
  "${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}/sample-app" \
  --include-tags
```

GitHub Actions가 push한 image tag를 `k8s/deployment.yaml`에 반영하고 Git에 커밋하면 Argo CD가 해당 desired state를 sync할 수 있다.

## 12. Prepare GitOps Desired State Image

Argo CD sync 검증을 위해 GitHub Actions가 push한 image tag를 `k8s/deployment.yaml`에 반영한다.

```bash
CI_TAG="$(git rev-parse HEAD)"
CI_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}/sample-app:${CI_TAG}"
sed -i "s#^          image: .*#          image: \"${CI_IMAGE}\"#" k8s/deployment.yaml
grep -n "image:" k8s/deployment.yaml
```

변경 내용을 확인하고 `k8s/deployment.yaml`만 Git에 반영한다.

```bash
git diff -- k8s/deployment.yaml
git add k8s/deployment.yaml
git commit -m "Update sample app image for Argo CD sync [skip ci]"
git push
```

이 커밋은 Argo CD가 실제 Artifact Registry image를 배포하도록 만드는 검증용 desired state다. `[skip ci]`를 붙여 manifest-only commit이 불필요하게 새 image를 build/push하지 않게 한다. 공개 template 상태를 유지하려면 Argo CD sync와 evidence 기록을 끝낸 뒤 16단계 cleanup 절차에서 placeholder로 되돌린다. 활성 Argo CD Application이 남아 있는 상태에서 placeholder를 push하면 Argo CD가 placeholder image로 다시 sync할 수 있다.

## 13. Install Argo CD

Argo CD 설치는 Terraform 범위 밖이다. Terraform state에는 Argo CD Helm release나 Kubernetes provider 리소스를 넣지 않으며, 이 runbook에서 cluster bootstrap 절차로만 수행한다.

Argo CD namespace를 만든다.

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
```

공식 install manifest를 server-side apply로 설치한다.

```bash
kubectl apply --server-side --force-conflicts \
  -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

상태를 확인한다.

```bash
kubectl -n argocd get pods
kubectl -n argocd get svc
```

모든 주요 Argo CD pod가 `Running` 또는 준비 상태가 될 때까지 기다린다.

## 14. Apply Argo CD Application

`gitops/argocd-app.yaml`의 `repoURL`을 확인한다.

```bash
grep -n "repoURL" gitops/argocd-app.yaml
```

아래 두 방법 중 하나만 실행한다. 이 repository 그대로 검증한다면 manifest를 바로 적용한다.

```bash
kubectl apply -f gitops/argocd-app.yaml
```

fork해서 쓰는 경우에는 위 명령 대신 repository 파일을 직접 수정하지 않고 임시 manifest의 `repoURL`만 본인 repository URL로 바꿔 적용한다.

```bash
ARGOCD_APP_MANIFEST="$(mktemp /tmp/argocd-app.XXXXXX.yaml)"
cp gitops/argocd-app.yaml "${ARGOCD_APP_MANIFEST}"
sed -i "s#repoURL: .*#repoURL: https://github.com/${GITHUB_REPO}.git#" "${ARGOCD_APP_MANIFEST}"
grep -n "repoURL" "${ARGOCD_APP_MANIFEST}"
kubectl apply -f "${ARGOCD_APP_MANIFEST}"
```

Argo CD Application 상태를 확인한다.

```bash
kubectl -n argocd get application gke-gitops-pipeline -o wide
kubectl -n argocd describe application gke-gitops-pipeline
```

기대 결과:

- Sync status `Synced`
- Health status `Healthy`
- Deployment `2/2` available

## 15. Record Evidence

실행 결과는 아래 문서에 기록한다.

| 기록 대상 | 문서 |
|---|---|
| 검증 명령과 결과 | `docs/07-validation.md` |
| 실패 원인과 해결 | `docs/08-troubleshooting.md` |
| 포트폴리오 설명 포인트 | `docs/09-portfolio-notes.md` |
| 캡처 파일 목록 | `docs/images/README.md` |

캡처는 `docs/images/`에 저장하고, 민감 값이 보이지 않는지 확인한다.

## 16. Cleanup

비용을 줄이려면 먼저 Kubernetes/Argo CD 리소스를 정리한 뒤 Terraform 리소스를 삭제한다.

```bash
kubectl -n argocd delete application gke-gitops-pipeline --ignore-not-found
kubectl delete -f k8s/ingress.yaml --ignore-not-found
kubectl delete -f k8s/service.yaml --ignore-not-found
kubectl delete -f k8s/deployment.yaml --ignore-not-found
kubectl delete namespace argocd --ignore-not-found
```

Ingress가 만든 GCP Load Balancer 리소스가 정리될 시간을 둔다.

```bash
kubectl get ingress sample-app --ignore-not-found
kubectl get svc sample-app --ignore-not-found
```

두 명령의 출력이 비거나 리소스가 `NotFound` 상태가 되면 Terraform destroy를 진행한다. GCP Console에서 forwarding rule, target proxy, backend service, NEG가 남아 있지 않은지도 비용 정리 관점에서 확인한다.

검증을 위해 `k8s/deployment.yaml`에 실제 image URI를 커밋했다면, 공개 template 상태로 되돌리는 커밋을 만든다. 이미 placeholder라면 이 절차는 건너뛴다. 이 작업은 Argo CD Application 삭제 후 또는 cluster cleanup 직전에 수행한다.

```bash
sed -i 's#^          image: .*#          image: "your-region-docker.pkg.dev/your-project-id/your-repository-id/sample-app:tag"#' k8s/deployment.yaml
git diff -- k8s/deployment.yaml
git add k8s/deployment.yaml
git commit -m "Restore sample app image placeholder [skip ci]"
git push
```

Terraform 리소스를 삭제한다.

```bash
terraform -chdir=terraform plan -destroy
terraform -chdir=terraform destroy
```

주의:

- `google_project_service`는 `disable_on_destroy = false`이므로 destroy해도 API 자체는 비활성화하지 않는다. Terraform은 API enablement 리소스를 state에서 제거하지만 project의 API는 켜진 상태로 남긴다.
- Artifact Registry image cleanup은 필요하면 별도 수행한다. repository를 유지하는 경우에는 image/tag를 직접 삭제한다.
- Static IP나 DNS 리소스는 현재 초기 범위에 포함하지 않는다.

Artifact Registry repository를 남겨 두고 image만 정리할 때는 tag를 확인한 뒤 필요한 항목만 삭제한다.

```bash
gcloud artifacts docker images list \
  "${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}/sample-app" \
  --include-tags

gcloud artifacts docker images delete \
  "${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPOSITORY}/sample-app:TAG_TO_DELETE" \
  --delete-tags
```

## 17. Common Failure Points

| 증상 | 확인 위치 |
|---|---|
| API enablement 실패 | GCP project 권한, billing, `serviceusage.googleapis.com` |
| Terraform GKE quota 실패 | SSD quota, node locations, disk size |
| `kubectl` 인증 실패 | `gke-gcloud-auth-plugin`, kubeconfig context, active gcloud account |
| image pull 실패 | GKE node service account, Artifact Registry reader IAM, image URI |
| 빈 커밋 대신 의도하지 않은 파일이 커밋됨 | `git status --short`, `git add .` 사용 여부 |
| GitHub Actions auth 실패 | WIF provider secret, service account secret, repository condition |
| Ingress address 미할당 | `kubernetes.io/ingress.class: "gce"`, Ingress events, GCP Load Balancer |
| Argo CD install CRD 오류 | server-side apply 사용 |
| Argo CD rollout 지연 | node resource, Deployment rolling update strategy |

자세한 실제 사례는 `docs/08-troubleshooting.md`를 참고한다.
