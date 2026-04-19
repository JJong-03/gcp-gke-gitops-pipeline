# Troubleshooting

이 문서는 프로젝트 진행 중 발생한 문제, 원인 분석, 해결 방법, 재발 방지 포인트를 기록한다.

단순 에러 메시지 모음이 아니라 문제를 어떻게 좁히고 해결했는지 보여주는 기록으로 관리한다. 실패한 검증 항목은 먼저 `docs/07-validation.md`에 `실패`로 남기고, 분석과 해결 과정은 이 문서에 작성한다.

## 현재 상태

`terraform apply` 1차 시도에서 GKE SSD quota 초과가 발생했고, 2차 시도에서는 cluster 임시 default pool `disk_size_gb = 10`이 GKE COS 이미지 최소 크기(12GB)보다 작아 실패했다. 이후 `disk_size_gb = 20`으로 상향하고 `project_id` 줄바꿈 입력 오류를 바로잡은 뒤 `terraform apply`가 성공했다. `gcloud container clusters list` 기준 GKE cluster는 `RUNNING`, node 수는 `2`로 확인됐다. 로컬 `kubectl`과 `gke-gcloud-auth-plugin` 누락 문제를 해결한 뒤 `kubectl get nodes`, `kubectl get pods -A` 검증도 완료했다. 로컬 Docker 미설치로 보류됐던 수동 image build/push smoke test도 Docker 준비 후 완료했다. GKE Ingress `ADDRESS` 미할당 문제는 `spec.ingressClassName` 단독 사용을 `kubernetes.io/ingress.class: "gce"` annotation으로 수정해 해결했고, External IP HTTP 200 응답까지 확인했다.

## 기록

### 2026-04-19 - GKE cluster 생성 중 SSD quota 초과

- 발생 시점: `terraform apply -var="project_id=warm-castle-493809-s1"` 실행 중 `module.gke.google_container_cluster.primary` 생성 단계
- 관련 영역: Terraform, GKE, quota
- 영향 범위: Artifact Registry, service account, IAM binding, VPC, subnet은 생성되었으나 GKE cluster가 정상 생성되지 않고 `ERROR` 상태로 남음
- 증상:
  - Terraform apply가 GKE cluster 생성 대기 중 실패
  - GKE cluster list에서 `gke-gitops-cluster`가 `ERROR` 상태로 표시됨
  - `NUM_NODES`는 `3`으로 표시되었으나 정상 `Ready` 검증은 아직 수행하지 않음
  - SSD quota 완화 목적으로 `google_container_cluster.primary.node_config.disk_size_gb = 10`을 적용한 뒤 apply를 재시도했으나, GKE node image 최소 크기보다 작아 다시 실패
- 확인한 명령/로그:

```text
terraform apply -var="project_id=warm-castle-493809-s1"
```

```text
Error waiting for creating GKE cluster: Insufficient quota to satisfy the request:
Not all instances running in IGM after 28.79783854s. Expected 1, running 0, transitioning 1.
Current errors: [GCE_QUOTA_EXCEEDED]:
Instance 'gke-gke-gitops-cluster-default-pool-d68f608a-lgvp' creation failed:
Quota 'SSD_TOTAL_GB' exceeded. Limit: 250.0 in region asia-northeast3.
```

```text
terraform state list
module.artifact_registry.google_artifact_registry_repository.docker
module.artifact_registry.google_artifact_registry_repository_iam_member.readers["gke_node"]
module.gke.google_container_cluster.primary
module.gke.google_project_iam_member.node_default_service_account
module.gke.google_service_account.node
module.network.google_compute_network.vpc
module.network.google_compute_subnetwork.gke
```

```text
gcloud container clusters list --region asia-northeast3 --project warm-castle-493809-s1
NAME                LOCATION         MASTER_VERSION                         MASTER_IP     MACHINE_TYPE  NODE_VERSION        NUM_NODES  STATUS  STACK_TYPE
gke-gitops-cluster  asia-northeast3  1.35.1-gke.1396002 (! 13 days left !)  34.22.82.153  e2-medium     1.35.1-gke.1396002  3          ERROR   IPV4
```

1차 quota 완화 수정 후 apply 재시도에서 발생한 추가 오류:

```text
terraform apply -var="project_id=warm-castle-493809-s1"
```

```text
Error waiting for creating GKE cluster: Google Compute Engine: googleapi: Error 400:
Invalid value for field 'resource.properties.disks[0].initializeParams.diskSizeGb': '10'.
Disk cannot be smaller than the chosen image 'gke-1351-gke1396002-cos-125-19216-104-126-c-pre' (12.0 GB)., invalid.
```

- 원인:
  - 최초 실패 원인: `asia-northeast3` 리전의 `SSD_TOTAL_GB` quota가 250GB인데, GKE cluster/node 생성 과정에서 필요한 SSD persistent disk quota가 이를 초과했다. 현재 Terraform은 regional cluster와 node locations `asia-northeast3-a`, `asia-northeast3-c`를 사용하고 있으며, 기본 node disk size가 명시적으로 낮게 설정되어 있지 않아 quota를 초과한 것으로 판단한다.
  - apply 재시도 실패 원인: quota 완화를 위해 cluster 임시 default pool disk size를 `10GB`로 낮췄지만, 현재 선택된 GKE COS image의 최소 크기가 `12GB`라서 Compute Engine disk 생성 요청이 거절되었다.
- 해결 시도:
  - 1차 Terraform 코드 수정 (2026-04-19). 아래 두 가지 변경을 적용했다.
  1. **node pool disk 축소**: `modules/gke/variables.tf`에 `disk_size_gb` 변수 추가 (기본값 `30`). root `variables.tf`에 `gke_node_disk_size_gb` 변수 추가 (기본값 `30`). `google_container_node_pool.primary` 의 `node_config.disk_size_gb`에 반영. `terraform.tfvars.example`에 `gke_node_disk_size_gb = 30` 추가.
  2. **임시 default pool disk 축소**: regional cluster는 `remove_default_node_pool = true`이더라도 cluster 생성 직후 임시로 3개 zone에 default pool 1개씩을 만든다. 기본 disk가 100GB이면 300GB(3 zone × 100GB)가 일시적으로 필요하여 quota를 초과한다. `google_container_cluster.primary`의 `node_config.disk_size_gb = 10`을 추가해 임시 default pool이 사용하는 SSD를 30GB(3 zone × 10GB)로 낮추려 했다.
  - 1차 수정의 예상 최대 SSD 사용량은 임시 default pool 30GB + 실제 node pool 60GB(2 zone × 1 node × 30GB) = 90GB였으나, `10GB`가 GKE image 최소 크기보다 작아 apply에는 실패했다.
  - 2차 수정 완료 (2026-04-19): cluster 임시 default pool disk size를 `10GB`→`20GB`로 상향. 예상 최대 SSD: 임시 default pool 60GB(3×20) + 실제 node pool 60GB(2×30) = 약 120GB. 250GB quota 내에서 수용 가능하다.
  - Quota 증설 신청은 후순위 개선으로 둔다.
- 검증: 1차 수정 후 `terraform plan -var="project_id=..."` 실행 완료 (2026-04-19). Plan 결과: `2 to add, 0 to change, 1 to destroy`. 이미 `ERROR` 상태인 cluster는 Terraform이 tainted로 처리하여 교체(destroy → recreate) 계획을 수립했다. 이후 `terraform apply` 재시도는 `disk_size_gb = 10`이 GKE image 최소 크기보다 작아 실패했다. `20GB`로 상향 수정한 뒤 한 줄 `project_id` 값으로 `terraform apply`를 재실행했고, `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.` 결과를 확인했다. 이어서 GKE cluster `RUNNING`, `NUM_NODES=2`를 확인했다. node readiness는 로컬 `kubectl`과 `gke-gcloud-auth-plugin` 설치 후 별도 검증이 필요하다.
- 재발 방지:
  - GKE node pool에 `disk_size_gb` 변수를 추가하고 낮은 기본값을 명시한다.
  - regional cluster의 `node_config.disk_size_gb`도 cluster resource에 명시해 임시 default pool의 SSD 사용량을 통제하되, GKE node image 최소 크기보다 작은 값은 사용하지 않는다.
  - cluster 임시 default pool disk size는 quota 절감과 image 최소 크기 조건을 모두 만족하는 값으로 둔다. 현재 적용값은 `20GB`다.
  - regional cluster에서 node count와 node locations 조합이 실제 disk quota에 미치는 영향을 문서화한다.
  - apply 전 quota와 예상 node disk 사용량을 확인한다.
  - Terraform state와 실제 리소스가 꼬이지 않도록 GCP Console에서 수동 삭제하거나 `terraform state`를 임의 조작하지 않는다.
- 관련 validation 항목: `docs/07-validation.md`의 `Terraform apply`, `GCP Console/CLI`, `GKE nodes`

### 2026-04-19 - Terraform project_id 값에 줄바꿈 포함

- 발생 시점: `terraform apply` 재시도 중 Artifact Registry repository, service account, VPC 생성 요청 단계
- 관련 영역: Terraform CLI 입력값, Google provider, project ID
- 영향 범위: Google provider가 project ID를 포함한 API URL을 만들 때 줄바꿈 문자가 포함되어 URL parsing과 service account 생성 요청이 실패함
- 증상:
  - Artifact Registry와 Compute Network API URL에 `warm-castle-493809-s1\n`이 포함되어 `invalid control character in URL` 오류 발생
  - service account 생성 요청에서 project 값 `warm-castle-493809-s1\n`이 project ID 정규식과 맞지 않는다는 `badRequest` 발생
- 확인한 명령/로그:

```text
Error creating Repository: parse "https://artifactregistry.googleapis.com/v1/projects/warm-castle-493809-s1
/locations/asia-northeast3/repositories?repository_id=gke-gitops-images":
net/url: invalid control character in URL
```

```text
Error creating service account: googleapi: Error 400: warm-castle-493809-s1
 does not match [a-z\d][a-z\d\-]*., badRequest
```

```text
Error creating Network: parse "https://compute.googleapis.com/compute/v1/projects/warm-castle-493809-s1
/global/networks": net/url: invalid control character in URL
```

- 원인: `project_id` 변수 값 끝에 newline control character가 들어갔다. 가장 가능성이 높은 원인은 `terraform apply -var="project_id=..."` 입력 중 따옴표 안에 줄바꿈이 포함되었거나, shell 변수 또는 `terraform.tfvars`에 project ID가 여러 줄 문자열처럼 저장된 것이다.
- 해결:
  - `project_id`를 반드시 한 줄 문자열로 전달한다.

```bash
terraform apply -var="project_id=warm-castle-493809-s1"
```

  - shell 변수를 쓸 경우 newline이 없는지 확인한다.

```bash
PROJECT_ID="warm-castle-493809-s1"
printf '%q\n' "$PROJECT_ID"
terraform apply -var="project_id=${PROJECT_ID}"
```

  - `terraform.tfvars`를 사용할 경우 아래처럼 한 줄로만 작성한다.

```hcl
project_id = "warm-castle-493809-s1"
```

- 검증: 한 줄 `project_id` 값으로 `terraform apply`를 재시도해 `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.` 결과를 확인했다.
- 재발 방지:
  - CLI에서 `-var` 값을 여러 줄로 붙여 넣지 않는다.
  - project ID는 가능하면 `terraform.tfvars`에 한 줄로 관리한다.
  - 오류 메시지에 `\n`, 줄바꿈된 URL, `invalid control character`가 보이면 입력값에 control character가 들어갔는지 먼저 확인한다.
- 관련 validation 항목: `docs/07-validation.md`의 `Terraform apply`

### 2026-04-19 - 로컬 kubectl 및 gke-gcloud-auth-plugin 누락

- 발생 시점: GKE cluster 생성 후 `gcloud container clusters get-credentials`, `kubectl get nodes`, `kubectl get pods -A` 실행 단계
- 관련 영역: GKE bootstrap, local tools, kubeconfig authentication
- 영향 범위: GKE cluster 자체는 `RUNNING`이지만 로컬에서 Kubernetes API, node readiness, system pod 상태를 아직 검증하지 못함
- 증상:
  - `gcloud container clusters list`에서는 `gke-gitops-cluster`가 `RUNNING`, `NUM_NODES=2`로 확인됨
  - `gcloud container clusters get-credentials`는 kubeconfig entry를 생성했지만 `gke-gcloud-auth-plugin` 누락 경고를 출력함
  - `kubectl get nodes`, `kubectl get pods -A`는 로컬에 `kubectl`이 없어 실행되지 않음
- 확인한 명령/로그:

```text
gcloud container clusters list --region asia-northeast3 --project [PROJECT_ID]
NAME                LOCATION         MASTER_VERSION      MASTER_IP    MACHINE_TYPE  NODE_VERSION        NUM_NODES  STATUS   STACK_TYPE
gke-gitops-cluster  asia-northeast3  1.35.1-gke.1396002  [REDACTED]   e2-medium     1.35.1-gke.1396002  2          RUNNING  IPV4
```

```text
gcloud container clusters get-credentials gke-gitops-cluster --region asia-northeast3 --project [PROJECT_ID]
CRITICAL: ACTION REQUIRED: gke-gcloud-auth-plugin, which is needed for continued use of kubectl, was not found or is not executable.
kubeconfig entry generated for gke-gitops-cluster.
```

```text
kubectl get nodes
Command 'kubectl' not found

kubectl get pods -A
Command 'kubectl' not found
```

- 원인: WSL/local shell에 Kubernetes CLI인 `kubectl`이 설치되어 있지 않고, GKE 인증에 필요한 `gke-gcloud-auth-plugin`도 설치되어 있지 않다. `get-credentials`가 kubeconfig entry를 생성했더라도 `kubectl` binary와 인증 plugin이 없으면 cluster bootstrap 검증을 진행할 수 없다.
- 해결:
  - 먼저 gcloud component 방식으로 설치를 시도한다.

```bash
gcloud components install kubectl gke-gcloud-auth-plugin
```

  - `gcloud components`가 apt/yum 패키지 설치 방식 때문에 비활성화되어 있으면 apt 패키지로 설치한다.

```bash
sudo apt-get update
sudo apt-get install -y kubectl google-cloud-sdk-gke-gcloud-auth-plugin
```

  - 환경에 따라 newer Google Cloud CLI 패키지명을 쓰는 경우 아래 패키지명이 필요할 수 있다.

```bash
sudo apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin
```

  - 설치 후 아래 순서로 다시 확인한다.

```bash
kubectl version --client
gke-gcloud-auth-plugin --version
gcloud container clusters get-credentials gke-gitops-cluster \
  --region asia-northeast3 \
  --project [PROJECT_ID]
kubectl get nodes
kubectl get pods -A
```

- 검증: 완료. 로컬 도구 설치 후 `kubectl get nodes`에서 node 2개가 모두 `Ready` 상태로 확인됐고, `kubectl get pods -A`에서 GKE managed/system pod가 `Running` 상태로 확인됐다. 결과는 `docs/07-validation.md`에 기록했다.
- 재발 방지:
  - GKE bootstrap 전 로컬 prerequisite에 `kubectl`과 `gke-gcloud-auth-plugin`을 포함한다.
  - `get-credentials` 성공 여부와 `kubectl` 접근 가능 여부를 분리해서 검증한다.
  - `sudo snap install kubectl`은 gcloud plugin 설치를 해결하지 않으므로, 가능하면 `gcloud components` 또는 Google Cloud CLI apt package 방식으로 맞춘다.
- 관련 validation 항목: `docs/07-validation.md`의 `GKE credentials`, `GKE nodes`, `System pods`

### 2026-04-19 - 로컬 Docker 미설치로 수동 image build 실패

- 발생 시점: Artifact Registry 수동 image build/push smoke test 중 `docker build -t "${IMAGE}" ./app` 실행 단계
- 관련 영역: local tools, Docker, Artifact Registry push, app deployment
- 영향 범위: 최초 시도에서는 `gcloud auth configure-docker`가 Docker config를 업데이트했지만, 로컬에 Docker CLI/daemon이 없어 sample app image build와 Artifact Registry push를 진행하지 못함
- 증상:
  - `gcloud auth configure-docker asia-northeast3-docker.pkg.dev` 실행 시 `docker not in system PATH` warning 발생
  - `docker build` 실행 시 `Command 'docker' not found`
- 확인한 명령/로그:

```text
gcloud auth configure-docker asia-northeast3-docker.pkg.dev
WARNING: `docker` not in system PATH.
`docker` and `docker-credential-gcloud` need to be in the same PATH in order to work correctly together.
Docker configuration file updated.
```

```text
docker build -t "${IMAGE}" ./app
Command 'docker' not found, but can be installed with:
sudo snap install docker
sudo apt  install docker.io
sudo apt  install podman-docker
```

- 원인: 현재 WSL/local shell에 Docker CLI가 설치되어 있지 않다. `gcloud auth configure-docker`는 credential helper 설정만 추가할 수 있으며, 실제 image build/push에는 Docker CLI와 동작 중인 Docker daemon이 필요하다.
- 해결:
  - Docker Desktop을 Windows에서 사용할 경우 WSL integration을 활성화한 뒤 WSL shell에서 `docker version`을 확인한다.
  - WSL 안에 Docker Engine을 설치해 진행할 경우 apt 패키지로 설치하고 daemon을 시작한다.

```bash
sudo apt update
sudo apt install -y docker.io
sudo usermod -aG docker "$USER"
newgrp docker
sudo service docker start
docker version
```

  - `newgrp docker` 이후에도 권한 문제가 있으면 WSL shell을 새로 열고 다시 확인한다. systemd가 활성화된 환경에서는 `sudo systemctl enable --now docker`를 사용할 수 있다.
  - 로컬 Docker를 설치하지 않을 경우 대안은 GitHub Actions WIF를 먼저 구성해 CI에서 build/push를 검증하는 것이다.
- 검증: 완료. Docker 준비 후 `docker build -t "${IMAGE}" ./app`가 성공했고, `docker push "${IMAGE}"`로 Artifact Registry에 `sample-app:manual-20260419201633` push가 완료됐다. Push digest는 `sha256:5dfd50c2beec17dcec619d841f492889224372037c1a58319a1b4fddcaf6e4a9`다. 결과는 `docs/07-validation.md`에 기록했다.
- 재발 방지:
  - 수동 image build/push 절차 전에 `docker version`을 local prerequisite로 확인한다.
  - `gcloud auth configure-docker` 성공과 실제 Docker build 가능 여부를 분리해서 검증한다.
  - Docker 설치 방식은 하나로 정하고, snap/apt/Docker Desktop을 섞지 않는다.
- 관련 validation 항목: `docs/07-validation.md`의 `Manual image build/push smoke test`, `Artifact Registry push`

### 2026-04-19 - GKE Ingress ADDRESS 미할당

- 발생 시점: `kubectl apply -f k8s/ingress.yaml` 후 `kubectl get ingress sample-app -w`로 external address를 대기하던 단계
- 관련 영역: Kubernetes Ingress, GKE Ingress Controller, External HTTP(S) Load Balancer
- 영향 범위: Service와 Pod는 정상이고 backend path도 보였지만, GKE-managed External HTTP(S) Load Balancer IP가 Ingress status에 기록되지 않아 외부 HTTP 접근 검증을 진행할 수 없었다.
- 증상:
  - `kubectl get ingress sample-app -w`에서 12분 이상 `ADDRESS`가 비어 있음
  - `kubectl describe ingress sample-app`에서 `Events: <none>`
  - `kubectl get ingressclass` 결과가 `No resources found`
  - Ingress manifest에는 `spec.ingressClassName: gce`만 있고 `kubernetes.io/ingress.class` annotation은 없음
- 확인한 명령/로그:

```text
kubectl get ingress sample-app -w
NAME         CLASS   HOSTS   ADDRESS   PORTS   AGE
sample-app   gce     *                 80      12m
```

```text
kubectl describe ingress sample-app
Address:
Ingress Class:    gce
Annotations:      <none>
Events:           <none>
```

```text
kubectl get ingressclass
No resources found
```

- 원인:
  - GKE Ingress Controller는 Kubernetes 표준의 `spec.ingressClassName`이 아니라 `kubernetes.io/ingress.class` annotation을 기준으로 처리 여부를 결정한다.
  - 공식 문서 기준으로 GKE는 annotation이 deprecated 되었더라도 계속 이 annotation을 사용하며, annotation이 없고 `ingressClassName`만 설정된 Ingress에는 GKE controller가 동작하지 않는다.
  - 따라서 `kubectl get ingress`의 `CLASS`에는 `gce`가 보였지만, 실제 GKE Load Balancer controller는 리소스를 처리하지 않아 `Events`와 `ADDRESS`가 비어 있었다.
- 해결:
  - `k8s/ingress.yaml`에서 `spec.ingressClassName: gce`를 제거하고, metadata annotation을 추가했다.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app
  annotations:
    kubernetes.io/ingress.class: "gce"
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: sample-app
                port:
                  name: http
```

  - 수정 후 Ingress를 다시 적용했다.

```bash
kubectl apply -f k8s/ingress.yaml
```

- 검증:
  - `kubectl describe ingress sample-app`에 `loadbalancer-controller` event가 생겼다.

```text
Normal  Sync       loadbalancer-controller  UrlMap "...sample-app..." created
Normal  Sync       loadbalancer-controller  TargetProxy "...sample-app..." created
Normal  Sync       loadbalancer-controller  ForwardingRule "...sample-app..." created
Normal  IPChanged  loadbalancer-controller  IP is now [INGRESS_IP]
```

  - `kubectl describe svc sample-app`에서 `cloud.google.com/neg-status`가 추가됐고, `kubectl get svcneg -A`에서 Service NEG 리소스가 확인됐다.
  - `gcloud compute backend-services get-health [SAMPLE_APP_BACKEND_SERVICE] --global --project [PROJECT_ID]`에서 sample app pod endpoints가 `HEALTHY`로 표시됐다.
  - IP 할당 직후에는 `curl http://[INGRESS_IP]/`가 `Empty reply from server` 또는 `Connection reset by peer`를 반환했지만, Load Balancer 전파 대기 후 `HTTP/1.1 200 OK`, `Via: 1.1 google`, placeholder HTML 응답을 확인했다.
- 재발 방지:
  - GKE Ingress를 사용할 때는 Kubernetes deprecation warning과 별개로 `kubernetes.io/ingress.class: "gce"` annotation을 사용한다.
  - `kubectl get ingress`의 `CLASS` 값만 보지 말고, `kubectl describe ingress`의 annotation, `loadbalancer-controller` events, GCP forwarding rule 생성 여부를 함께 확인한다.
  - `ADDRESS`가 오래 비어 있고 events가 없으면 controller가 Ingress를 처리하지 않는 상태를 먼저 의심한다.
  - IP가 할당된 직후 external `curl` 실패는 backend health와 URL map을 확인하고, health가 정상이라면 Load Balancer 전파 시간을 두고 재시도한다.
- 참고 기준:
  - Google Cloud GKE Ingress 문서: `kubernetes.io/ingress.class` annotation 값에 따라 GKE Ingress Controller 처리 여부가 결정되며, GKE Ingress는 deprecated warning과 별개로 이 annotation을 계속 사용한다.
- 관련 validation 항목: `docs/07-validation.md`의 `Ingress`, `Ingress backend/events`, `External access`

### 2026-04-19 - WIF provider 생성 명령 줄바꿈 및 placeholder repo 값

- 발생 시점: GitHub Actions용 Workload Identity Federation provider 생성 단계
- 관련 영역: GitHub Actions, GCP Workload Identity Federation, shell command 입력
- 영향 범위: deploy service account, Artifact Registry writer 권한, Workload Identity Pool은 생성됐지만, Workload Identity Provider와 service account impersonation binding은 아직 생성되지 않음. 따라서 GitHub Actions push job은 아직 Google Cloud 인증을 할 수 없다.
- 증상:
  - `gcloud iam workload-identity-pools providers create-oidc` 실행 중 `--attribute-mapping` option이 줄바꿈되어 `--attribute-`로 잘림
  - gcloud가 `--attribute-`를 알 수 없는 인자로 처리
  - 다음 줄의 `--attribute-condition=...`이 shell 명령처럼 실행되어 `No such file or directory` 발생
  - `GITHUB_OWNER=OWNER`, `GITHUB_REPO=REPOSITORY` placeholder 값이 실제 repository 값으로 교체되지 않은 상태
- 확인한 명령/로그:

```text
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
  ...
  --attribute-
mapping="google.subject=assertion.sub,..."
```

```text
ERROR: (gcloud.iam.workload-identity-pools.providers.create-oidc) unrecognized arguments: --attribute- (did you mean '--attribute-mapping'?)
bash: --attribute-condition=assertion.repository=='OWNER/REPOSITORY': No such file or directory
```

- 원인:
  - shell option 이름이 중간에서 줄바꿈되어 `--attribute-mapping`이 하나의 인자로 전달되지 않았다.
  - `OWNER/REPOSITORY`는 예시 placeholder인데 실제 GitHub repository 값으로 바꾸지 않았다. 이 값 그대로 provider를 만들면 GitHub OIDC 조건이 가짜 repository에 묶여 실제 workflow 인증이 실패한다.
- 해결:
  - 이미 성공한 리소스는 재생성하지 않는다.
    - deploy service account: `github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com`
    - Artifact Registry writer binding
    - Workload Identity Pool: `github-actions`, state `ACTIVE`
  - 실제 GitHub repository를 먼저 확정한다.

```bash
GITHUB_OWNER="actual-github-owner"
GITHUB_REPO="actual-repository-name"
```

  - provider 생성 명령은 `--attribute-mapping`을 한 줄 옵션으로 붙여넣거나, 아래처럼 shell 변수를 사용해 줄바꿈 위험을 줄인다.

```bash
ATTRIBUTE_MAPPING="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.actor=assertion.actor"
ATTRIBUTE_CONDITION="assertion.repository=='${GITHUB_OWNER}/${GITHUB_REPO}'"

gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="${POOL_ID}" \
  --display-name="GitHub ${GITHUB_OWNER}/${GITHUB_REPO}" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="${ATTRIBUTE_MAPPING}" \
  --attribute-condition="${ATTRIBUTE_CONDITION}"
```

- 검증:
  - 현재 확인 완료:
    - deploy service account 조회 성공
    - Artifact Registry repository IAM에서 deploy service account의 `roles/artifactregistry.writer` 확인
    - Workload Identity Pool `github-actions` state `ACTIVE`
    - provider list는 비어 있어 provider 미생성 확인
  - 추가 실패와 해결:
    - 실제 GitHub repository 값을 `JJong-03/gcp-gke-gitops-pipeline`으로 바꾼 뒤 provider 생성을 재시도했으나, `--display-name="GitHub JJong-03/gcp-gke-gitops-pipeline"` 값이 32자를 초과해 `INVALID_ARGUMENT: display name must be less than or equal to 32 characters` 오류가 발생했다.
    - provider ID와 repository condition은 유지하고 display name만 `GitHub Actions`로 줄여 provider 생성을 완료했다.
  - 최종 확인 완료:
    - provider `projects/258687934668/locations/global/workloadIdentityPools/github-actions/providers/gke-gitops-pipeline` state `ACTIVE`
    - provider attribute condition `assertion.repository=='JJong-03/gcp-gke-gitops-pipeline'`
    - deploy service account IAM policy에서 repository-scoped `roles/iam.workloadIdentityUser` principal binding 확인
  - 아직 필요한 검증:
    - GitHub repository variables/secrets 등록
    - GitHub Actions `workflow_dispatch` build-only 및 `main` push image push 검증
- 재발 방지:
  - 긴 gcloud option은 중간 줄바꿈 없이 붙여넣거나 shell 변수로 분리한다.
  - `OWNER`, `REPOSITORY`, `YOUR_PROJECT_ID` 같은 placeholder는 실행 전에 반드시 실제 값으로 바꾼다.
  - Workload Identity Provider display name은 32자 이하로 둔다. 긴 repo 이름은 provider ID나 attribute condition에만 사용하고 display name은 짧게 유지한다.
  - 이미 생성된 GCP 리소스는 재생성하지 말고 `describe`/`list`로 상태를 확인한 뒤 실패한 단계부터 이어간다.
- 관련 validation 항목: `docs/07-validation.md`의 `GitHub OIDC/WIF prerequisite`

### 2026-04-19 - GitHub Actions initial push가 variables/secrets 등록 전 실패

- 발생 시점: `git push -u origin main` 후 GitHub Actions `CI #1` 실행
- 관련 영역: GitHub Actions, repository variables/secrets, CI image build
- 영향 범위: repository push는 성공했고 workflow run은 생성됐지만, `build` job이 실패해 Docker image build와 Artifact Registry push 검증이 완료되지 않음
- 증상:
  - GitHub repository `JJong-03/gcp-gke-gitops-pipeline`에 commit `c28b5d1` push 완료
  - GitHub Actions run `Build GKE GitOps pipeline baseline #1` 생성
  - run #1 status `Failure`, total duration `7s`
  - `Build image` job이 exit code `1`
  - `Push image` job은 `0s`로 실행되지 않음
- 확인한 명령/로그:

```text
git remote -v
origin  https://github.com/JJong-03/gcp-gke-gitops-pipeline.git (fetch)
origin  https://github.com/JJong-03/gcp-gke-gitops-pipeline.git (push)

git rev-parse HEAD
c28b5d1084c496897667321df6102090f9ad0150
```

```text
GitHub Actions
Build GKE GitOps pipeline baseline #1
Triggered via push
Status Failure
Total duration 7s
Build image: Process completed with exit code 1
Push image: 0s
```

- 원인:
  - 현재 local 환경에는 `gh` CLI가 없어 GitHub variables/secrets 등록 상태를 CLI로 직접 확인하지 못했다.
  - workflow의 첫 job은 `GCP_PROJECT_ID`, `GCP_REGION`, `ARTIFACT_REGISTRY_REPOSITORY` 값을 검증한다. initial push 전에 GitHub repository variables/secrets를 등록하지 않았다면 `GCP_PROJECT_ID`가 비어 있어 의도한 fail-fast 검증에서 실패한다.
  - public GitHub page에서는 sign-in 없이 상세 step log를 볼 수 없어 정확한 실패 line은 GitHub UI에서 확인해야 한다. 현재 관측 정보상 repository variables 미등록이 가장 가능성이 높다.
- 해결:
  - GitHub repository settings에서 Actions variables/secrets를 등록한다.

```text
Variables:
GCP_PROJECT_ID = warm-castle-493809-s1
GCP_REGION = asia-northeast3
ARTIFACT_REGISTRY_REPOSITORY = gke-gitops-images

Secrets:
GCP_WORKLOAD_IDENTITY_PROVIDER = projects/258687934668/locations/global/workloadIdentityPools/github-actions/providers/gke-gitops-pipeline
GCP_SERVICE_ACCOUNT = github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com
```

  - 등록 후 GitHub Actions run #1에서 `Re-run all jobs`를 실행하거나, 아래처럼 빈 commit으로 새 push event를 만든다.

```bash
git commit --allow-empty -m "Trigger CI workflow"
git push
```

- 검증:
  - 완료. GitHub repository variables/secrets 등록 후 commit `e3a889e3cf74ba0491c60436492a085fe3419f4f` push에서 Artifact Registry에 `sample-app:e3a889e3cf74ba0491c60436492a085fe3419f4f` tag가 생성됐다.
  - 확인된 digest: `sha256:5612a9a865a5037fbf4c0a3f742251ed54d54f9396d2e517544f000efcb3c001`
  - 이 결과로 GitHub Actions build/push와 WIF 인증, Artifact Registry writer 권한이 동작했음을 확인했다.
- 재발 방지:
  - 첫 push 전에 repository variables/secrets를 먼저 등록한다.
  - workflow에 둔 `Validate workflow configuration` 단계는 변수 누락을 빠르게 드러내기 위한 의도적 fail-fast 단계이므로 유지한다.
  - public page에서 logs가 제한되면 GitHub에 로그인한 상태로 run detail을 확인한다.
- 관련 validation 항목: `docs/07-validation.md`의 `GitHub repository variables/secrets`, `GitHub Actions build`, `Artifact Registry push (CI)`

## 기록 대상

| 영역 | 기록할 예시 |
|---|---|
| Terraform | provider 초기화 실패, plan/apply 오류, API enablement 문제, quota 문제 |
| GKE bootstrap | credentials 획득 실패, IAM 권한 문제, kubeconfig context 문제 |
| Kubernetes | image pull 실패, `roles/container.defaultNodeServiceAccount` 누락, Artifact Registry reader IAM 누락, readiness/liveness probe 실패, Service selector 불일치 |
| Ingress | external address 미할당, NEG annotation/status 미생성, backend health check 실패, host 설정 문제 |
| GitHub Actions | Google Cloud 인증 실패, Docker build 실패, Artifact Registry push 실패 |
| Argo CD | repoURL 오류, manifest sync 실패, application health 비정상 |

## 기록 템플릿

```text
### YYYY-MM-DD - 문제 제목

- 발생 시점:
- 관련 영역:
- 영향 범위:
- 증상:
- 확인한 명령/로그:
- 원인:
- 해결:
- 검증:
- 재발 방지:
- 관련 validation 항목:
```

## 작성 기준

- 실제로 발생한 문제만 기록한다.
- 해결된 문제라도 원인과 검증 결과를 함께 남긴다.
- 공개하면 안 되는 project ID, token, credential, 계정 정보는 제거한다.
- 같은 문제가 반복되면 기존 항목에 재발 방지 내용을 보강한다.
- 원인이 불명확하면 추측으로 확정하지 말고 “현재 추정”으로 표시한다.

## Validation 문서와의 연결

| 상황 | 처리 |
|---|---|
| 검증 성공 | `docs/07-validation.md`에만 기록 |
| 검증 실패 후 바로 해결 | `docs/07-validation.md`에 실패와 재실행 결과를 남기고, 이 문서에 원인/해결 기록 |
| 장기 미해결 | `docs/07-validation.md` 상태를 `실패` 또는 `보류`로 두고, 이 문서에 현재 분석 상태 기록 |
