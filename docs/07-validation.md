# Validation

이 문서는 프로젝트의 각 단계가 실제로 동작했는지 검증한 명령어, 기대 결과, 실제 결과, 증거 위치를 기록한다.

계획이나 기대 결과만으로 완료 처리하지 않는다. 실제로 실행한 항목만 `완료`로 바꾸고, 실패한 항목은 `실패`로 기록한 뒤 `docs/08-troubleshooting.md`에 연결한다.

## 상태 값

| 상태 | 의미 |
|---|---|
| 대기 | 아직 실행하지 않음 |
| 진행 중 | 일부 구현 또는 검증은 완료됐지만 import, plan, 외부 확인 등 후속 검증이 남음 |
| 완료 | 실행했고 기대 결과와 일치함 |
| 실패 | 실행했지만 실패 또는 기대 결과 불일치 |
| 보류 | 외부 조건이나 결정이 필요함 |
| not covered | 이번 검증 증거 범위에 포함하지 않음 |
| future validation | 후속 개선 단계에서 검증 예정 |

## 검증 매트릭스

| 단계 | 명령/확인 항목 | 기대 결과 | 실제 결과 | 상태 | 증거/링크 | 관련 문서 |
|---|---|---|---|---|---|---|
| GCP API enablement | `gcloud services enable compute.googleapis.com container.googleapis.com artifactregistry.googleapis.com serviceusage.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com` | 필요한 API가 활성화됨 | 수동 활성화 완료 | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md` |
| GCP API enablement Terraform code | `project_services` module, `terraform import`, `terraform plan` | 필요한 API가 `google_project_service`로 표현되고 `disable_on_destroy = false`가 적용됨 | 코드 추가, `terraform validate` 성공, 기존 8개 API import 완료. post-import `terraform plan` `No changes.` 확인 | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md` |
| GitHub OIDC/WIF GCP manual setup | Workload Identity Provider, deploy service account, `roles/iam.workloadIdentityUser` 확인 | GitHub Actions가 service account로 인증 가능한 GCP 측 수동 구성 | deploy service account, Artifact Registry writer 권한, WIF pool/provider, repository-scoped `roles/iam.workloadIdentityUser` binding 완료 | 완료 | 2026-04-19 local, `docs/08-troubleshooting.md` | `docs/06-gitops-cicd.md` |
| GitHub OIDC/WIF Terraform code | `github_wif` module, `terraform import`, `terraform plan` | deploy service account, Artifact Registry writer IAM, WIF pool/provider, repository-scoped impersonation binding이 Terraform으로 표현됨 | 코드 추가, `terraform validate` 성공, 5개 리소스 import 완료. post-import `terraform plan` `No changes.` 확인 | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md`, `docs/06-gitops-cicd.md` |
| GitHub repository variables/secrets | Repository Actions variables/secrets 확인 | workflow가 project/region/repository 값과 WIF secret을 사용할 수 있음 | 등록 후 commit `e3a889e...` push에서 CI image가 Artifact Registry에 생성되어 간접 검증 완료 | 완료 | 2026-04-19 GitHub/GCP | `docs/06-gitops-cicd.md`, `docs/08-troubleshooting.md` |
| Terraform init | `terraform init` | provider와 module 초기화 성공 | `hashicorp/google v5.45.2` 설치, 모듈 초기화 완료 | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md` |
| Terraform validate | `terraform validate` | Terraform syntax와 provider schema 검증 성공 | `Success! The configuration is valid.` | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md` |
| Terraform plan (1차) | `terraform plan -var="project_id=..."` | VPC, subnet, GKE, Artifact Registry 생성 계획 확인 | 8 resources to add. `readers["gke_node"]` key가 정적 map으로 정상 resolve됨 | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md` |
| Terraform plan (disk 수정 후) | `terraform plan -var="project_id=..."` | GKE cluster replace + node pool create 계획 확인 | 2 to add, 0 to change, 1 to destroy. cluster replace(tainted), node pool create. 기존 리소스 변경 없음. | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md` |
| Terraform apply (1차) | `terraform apply -var="project_id=[PROJECT_ID]"` | GCP 리소스 생성 성공 | Artifact Registry, SA, IAM, VPC, subnet은 생성 완료. GKE cluster는 SSD quota 초과로 `ERROR` 상태. node pool 미생성. | 실패 | 2026-04-19 local, `docs/08-troubleshooting.md` | `docs/03-terraform-plan.md`, `docs/08-troubleshooting.md` |
| Terraform apply (2차 — disk 10GB) | `terraform apply -var="project_id=[PROJECT_ID]"` | GKE cluster와 node pool 정상 생성 | GKE COS 이미지 최소 크기 12GB보다 작은 10GB 지정으로 실패. 이후 cluster `node_config.disk_size_gb = 20`으로 수정해 3차 apply에서 해결됨. | 실패 | 2026-04-19 local, `docs/08-troubleshooting.md` | `docs/03-terraform-plan.md`, `docs/08-troubleshooting.md` |
| Terraform plan (disk 20GB 수정 후) | `terraform plan -var="project_id=..."` | GKE cluster replace + node pool create, disk 20GB 반영 확인 | 2 to add, 0 to change, 1 to destroy. cluster node_config `disk_size_gb: 10 → 20` 반영. node pool `disk_size_gb = 30`, `node_locations = [asia-northeast3-a, asia-northeast3-c]` 정상. | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md` |
| Terraform apply (3차 — disk 20GB) | `terraform apply -var="project_id=[PROJECT_ID]"` | GKE cluster와 node pool 정상 생성 | `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.` Outputs: `gke_cluster_name=gke-gitops-cluster`, `gke_cluster_location=asia-northeast3`, `artifact_registry_repository_id=gke-gitops-images`, `gke_node_service_account_email=gke-gitops-node@[PROJECT_ID].iam.gserviceaccount.com`, `network_name=gke-gitops-vpc`, `subnet_name=gke-gitops-subnet` | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md`, `docs/08-troubleshooting.md` |
| GKE cluster status | `gcloud container clusters list --region asia-northeast3 --project [PROJECT_ID]`, GCP Console cluster 확인 | cluster `STATUS`가 `RUNNING`이고 node 수가 node pool 설계와 일치 | `gke-gitops-cluster`가 `RUNNING`, `NUM_NODES`는 `2`. GCP Console 캡처로 cluster running 상태와 node 수 확인 | 완료 | 2026-04-19 local, `docs/images/02-gke-cluster-running.png` | `docs/04-gke-bootstrap.md` |
| GCP Console - VPC/subnet secondary ranges | GCP Console VPC subnet 상세 확인 | Terraform network module의 subnet과 Pod/Service secondary IP range가 GCP에 생성됨 | `gke-gitops-subnet`과 Pod/Service secondary IP range가 Console 캡처로 확인됨 | 완료 | `docs/images/19-gcp-vpc-subnet-secondary-ranges.png` | `docs/03-terraform-plan.md`, `docs/images/README.md` |
| GCP Console - Artifact Registry tags | GCP Console Artifact Registry image tags 확인 | 수동 push tag와 GitHub Actions commit SHA tag가 repository에 존재 | `manual-*` tag와 commit SHA tag가 Console 캡처로 확인됨 | 완료 | `docs/images/18-gcp-artifact-registry-console-tags.png` | `docs/05-app-deployment.md`, `docs/06-gitops-cicd.md`, `docs/images/README.md` |
| GCP Console - Load Balancer / Ingress | GCP Console Load Balancer 상세 확인 | GKE Ingress가 생성한 external load balancer와 backend 연결 확인 | Ingress external IP와 backend 연결이 Console Load Balancer 상세 캡처로 확인됨 | 완료 | `docs/images/17-gcp-load-balancer-ingress-detail.png` | `docs/05-app-deployment.md`, `docs/images/README.md` |
| GCP Console/CLI - future validation scope | Cloud DNS, Managed Certificate, static IP, HTTPS 고정 구성, Terraform remote backend | 초기 범위 밖 항목은 완료로 표시하지 않고 후속 개선으로 관리 | 초기 버전 검증 증거에 포함하지 않음. README의 Planned Improvements에 남김 | future validation | not covered by current captures | `README.md` |
| GKE node service account IAM | Terraform output, project IAM policy, Artifact Registry IAM policy 확인 | GKE node service account에 project-level `roles/container.defaultNodeServiceAccount`와 repository-scoped `roles/artifactregistry.reader`가 부여됨 | 두 IAM binding 모두 GKE node service account에 부여됨 | 완료 | 2026-04-19 local | `docs/03-terraform-plan.md`, `docs/05-app-deployment.md` |
| GKE credentials | `gcloud container clusters get-credentials` | kubeconfig context 생성 | kubeconfig entry 생성 후 로컬 `kubectl` 접근 성공 | 완료 | 2026-04-19 local | `docs/04-gke-bootstrap.md` |
| GKE nodes | `kubectl get nodes` | node가 `Ready` 상태 | node 2개가 모두 `Ready`, version `v1.35.1-gke.1396002` | 완료 | 2026-04-19 local | `docs/04-gke-bootstrap.md` |
| System pods | `kubectl get pods -A` | system pod가 정상 상태 | `gke-managed-cim`, `gmp-system`, `kube-system` pod가 `Running` 상태 | 완료 | 2026-04-19 local | `docs/04-gke-bootstrap.md` |
| Manual image build/push smoke test | `gcloud auth configure-docker`, `docker build`, `docker push` | local Docker로 sample app image를 build하고 Artifact Registry에 push | `sample-app:manual-20260419201633` build/push 성공. Digest `sha256:5dfd50c2beec17dcec619d841f492889224372037c1a58319a1b4fddcaf6e4a9` | 완료 | 2026-04-19 local | `docs/05-app-deployment.md`, `docs/06-gitops-cicd.md` |
| App deployment | `kubectl apply -f k8s/deployment.yaml`, `kubectl rollout status deployment/sample-app`, `kubectl get deploy,pods` | `sample-app` deployment와 pod 정상 | deployment 생성, rollout 성공, `2/2` available, pod 2개 `Running` | 완료 | 2026-04-19 local | `docs/05-app-deployment.md` |
| GKE image pull | `kubectl describe pod -l app=sample-app` | Artifact Registry image pull 성공 | 두 pod 모두 `sample-app:manual-20260419201633` image pull 성공. Image ID digest `sha256:5dfd50c2beec17dcec619d841f492889224372037c1a58319a1b4fddcaf6e4a9` | 완료 | 2026-04-19 local | `docs/05-app-deployment.md` |
| App service | `kubectl get svc sample-app` | ClusterIP service 확인 | `sample-app` Service 생성, `TYPE=ClusterIP`, `CLUSTER-IP=10.30.7.71`, port `80/TCP` | 완료 | 2026-04-19 local | `docs/05-app-deployment.md` |
| Service NEG status | `kubectl describe svc sample-app`, `kubectl get svcneg -A` | NEG 관련 annotation/status 확인, 미생성 시 Ingress event와 함께 원인 추적 | `cloud.google.com/neg`와 `cloud.google.com/neg-status` 확인, `svcneg` 생성, endpoints `10.20.1.6:80`, `10.20.1.5:80` | 완료 | 2026-04-19 local | `docs/05-app-deployment.md` |
| Ingress | `kubectl get ingress sample-app` | host rule 없는 Ingress의 external address 또는 provisioning 상태 확인 | GKE class annotation 반영 후 External IP 할당 완료. hosts `*`, port `80` | 완료 | 2026-04-19 local | `docs/05-app-deployment.md`, `docs/08-troubleshooting.md` |
| Ingress backend/events | `kubectl describe ingress sample-app`, `gcloud compute backend-services get-health` | backend 연결 상태와 events 확인 | UrlMap, TargetProxy, ForwardingRule 생성. sample app backend `HEALTHY` 확인 | 완료 | 2026-04-19 local | `docs/05-app-deployment.md` |
| External access | External IP HTTP 접근 확인 | placeholder app 응답 확인 | 전파 대기 후 `curl http://[INGRESS_IP]/`에서 `HTTP/1.1 200 OK`, `Via: 1.1 google`, placeholder HTML 응답 확인 | 완료 | 2026-04-19 local | `docs/05-app-deployment.md` |
| GitHub repository push | `git push -u origin main`, GitHub repository 확인 | main branch에 repository baseline push | GitHub repository `[OWNER]/[REPOSITORY]`에 commit `c28b5d1` push 완료, workflow run #1 생성 | 완료 | 2026-04-19 GitHub | `docs/06-gitops-cicd.md` |
| GitHub Actions build | workflow `build` job 확인 | Docker image build 성공 | commit `e3a889e...` push 후 Artifact Registry에 matching image tag가 생성되어 build/push flow 성공 확인 | 완료 | 2026-04-19 GitHub/GCP | `docs/06-gitops-cicd.md` |
| Artifact Registry push (CI) | GitHub Actions workflow `push` job 또는 registry 확인 | `sample-app:${GITHUB_SHA}` image push 확인 | `sample-app:e3a889e3cf74ba0491c60436492a085fe3419f4f` 생성 확인. Digest `sha256:5612a9a865a5037fbf4c0a3f742251ed54d54f9396d2e517544f000efcb3c001` | 완료 | 2026-04-19 GCP | `docs/06-gitops-cicd.md` |
| Argo CD sync | Argo CD Application 확인 | sync status `Synced`, health `Healthy` | Argo CD 설치 후 Application `Synced/Healthy`, revision `13572bdb7928e7bd59393738091bd925e06b1163`, Deployment `2/2` rollout 완료 | 완료 | 2026-04-19 local/GKE | `docs/06-gitops-cicd.md`, `docs/08-troubleshooting.md` |

## 실행 기록 템플릿

검증 항목을 실행한 뒤 아래 형식으로 같은 문서에 짧게 기록한다.

```text
### YYYY-MM-DD - 검증 항목

- 명령:
- 기대 결과:
- 실제 결과:
- 상태:
- 증거:
- 관련 이슈:
```

### 2026-04-19 - Bootstrap prerequisite Terraformization code validation

- 명령: `terraform state list`
- 기대 결과: 기존 Terraform state가 VPC, subnet, GKE, node IAM, Artifact Registry 범위만 포함하고 API/WIF 리소스는 아직 import되지 않았음을 확인
- 실제 결과: 기존 state는 `module.network`, `module.gke`, `module.artifact_registry` 리소스 8개만 포함. `project_services`, `github_wif` 리소스는 아직 state에 없음
- 상태: 완료

- 변경 내용: `terraform/modules/project_services`와 `terraform/modules/github_wif` 추가. root module에 `enabled_project_services`, `project_number`, `github_owner`, `github_repository`, WIF ID 변수와 관련 output 연결
- 상태: 진행 중

- 명령: `terraform fmt -recursive`
- 실제 결과: 성공
- 상태: 완료

- 명령: `terraform init`
- 실제 결과: 성공. 신규 local module `project_services`, `github_wif` 등록, 기존 `hashicorp/google v5.45.2` provider 재사용
- 상태: 완료

- 명령: `terraform validate`
- 실제 결과: `Success! The configuration is valid.`
- 상태: 완료

- 남은 검증: 기존 수동 활성화 API와 GitHub Actions WIF GCP-side 리소스를 import한 뒤 `terraform plan`에서 예상치 못한 destroy/recreate가 없는지 확인해야 함. `terraform apply`는 plan review 전 실행하지 않음.
- 상태: 진행 중
- 후속 연결: 이 중간 상태는 이후 기존 수동 리소스 import와 post-import `terraform plan` `No changes.` 확인으로 완료 처리됐다.

### 2026-04-19 - Bootstrap prerequisite Terraform import 및 plan 안정화

- 대상: `module.project_services` 8개 API, `module.github_wif` 5개 리소스 (총 13개)
- 명령: `terraform import` (TF_VAR 환경변수 기반, 리소스별 one-line command)
- 실제 결과: 13개 import 모두 성공. post-import 초기 plan에서 WIF pool/provider `# forces replacement` 발생.
- 원인: WIF pool/provider import ID가 project number 기반이라 state에 `project = "[PROJECT_NUMBER]"`이 저장됐지만 코드는 `project = var.project_id`(문자 ID)여서 provider가 불일치 감지 후 recreate 계획
- 코드 수정: `modules/github_wif/main.tf`의 WIF pool/provider `project` 필드를 `var.project_number`로 변경. `attribute_condition` 포맷도 GCP 저장 형식(`assertion.repository=='...'`)에 맞춤.
- 추가 drift: `google_container_cluster.primary.node_config.disk_size_gb = 30 → 20`. default node pool 삭제 후 GCP API가 node_config를 기본값(30GB)으로 반환하기 때문. 실제 workload node는 `google_container_node_pool.primary`가 관리하므로 `lifecycle { ignore_changes = [node_config] }` 추가.
- WIF description drift: import 당시 description이 GCP에 없어 plan에서 `+ description` 노이즈 발생. 코드에서 description 필드를 제거해 no-op으로 해결.
- 최종 `terraform plan` 결과: `No changes. Your infrastructure matches the configuration.`
- 상태: 완료

### 2026-04-19 - Terraform init / validate / fmt

- 명령: `terraform init`
- 실제 결과: 성공. `hashicorp/google v5.45.2` 설치, `network`, `gke`, `artifact_registry` 모듈 초기화 완료
- 상태: 완료

- 명령: `terraform fmt -recursive`
- 실제 결과: 성공, 수정 파일 없음
- 상태: 완료

- 명령: `terraform validate`
- 실제 결과: `Success! The configuration is valid.`
- 상태: 완료

### 2026-04-19 - terraform apply 1차 시도 (GKE quota 실패)

- 명령: `terraform apply -var="project_id=[PROJECT_ID]"`
- 기대 결과: 전체 리소스 생성 성공
- 실제 결과: network, subnet, Artifact Registry, service account, IAM binding 생성 완료. GKE cluster 생성 중 `Quota 'SSD_TOTAL_GB' exceeded. Limit: 250.0 in region asia-northeast3` 오류 발생. cluster가 `ERROR` 상태로 남고 node pool은 미생성.
- 상태: 실패
- 관련 이슈: `docs/08-troubleshooting.md` — GKE cluster 생성 중 SSD quota 초과

### 2026-04-19 - disk_size_gb 수정 후 plan 재확인 (1차)

- 변경 내용: node pool `disk_size_gb = 30`, cluster `node_config.disk_size_gb = 10` 추가. root/module 변수 추가.
- 명령: `terraform fmt -recursive && terraform validate && terraform plan -var="project_id=[PROJECT_ID]"`
- 실제 결과: `Plan: 2 to add, 0 to change, 1 to destroy`. ERROR 상태 cluster는 tainted 처리되어 replace(destroy→recreate). node pool은 신규 create. 기존 network, Artifact Registry, SA, IAM 리소스 변경 없음.
- 상태: 완료
- 관련 이슈: `terraform apply` 재시도 시 disk 10GB가 GKE COS 이미지 최소 12GB보다 작아 실패

### 2026-04-19 - terraform apply 2차 시도 (GKE disk 크기 오류)

- 명령: `terraform apply -var="project_id=[PROJECT_ID]"`
- 기대 결과: GKE cluster와 node pool 정상 생성
- 실제 결과: `Error 400: Invalid value for field 'resource.properties.disks[0].initializeParams.diskSizeGb': '10'. Disk cannot be smaller than the chosen image 'gke-1351-gke1396002-cos-125-19216-104-126-c-pre' (12.0 GB).` — GKE COS 이미지 최소 크기 12GB보다 작아 실패.
- 상태: 실패
- 관련 이슈: `docs/08-troubleshooting.md` — GKE cluster 생성 중 SSD quota 초과 (2차 실패 내용 포함)

### 2026-04-19 - disk_size_gb 20GB 수정 후 plan 재확인 (2차)

- 변경 내용: cluster `node_config.disk_size_gb = 10` → `20`으로 상향. GKE COS 이미지 최소 12GB 대응.
- 명령: `terraform fmt -recursive && terraform validate && terraform plan -var="project_id=[PROJECT_ID]"`
- 실제 결과: `terraform fmt` 수정 없음. `terraform validate` → `Success! The configuration is valid.`. `terraform plan` → `Plan: 2 to add, 0 to change, 1 to destroy`. cluster replace(tainted→recreate) 계획에서 `disk_size_gb: 10 → 20` 반영 확인. node pool `disk_size_gb = 30`, `node_locations = [asia-northeast3-a, asia-northeast3-c]`, `node_count = 1` 정상 반영.
- 상태: 완료
- 관련 이슈: 이후 3차 `terraform apply`에서 해결 확인

### 2026-04-19 - terraform apply 3차 성공

- 명령: `terraform apply -var="project_id=[PROJECT_ID]"`
- 기대 결과: GKE cluster와 node pool을 포함한 GCP 리소스 생성 성공
- 실제 결과: `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.`
- Outputs:
  - `artifact_registry_repository_id = "gke-gitops-images"`
  - `gke_cluster_location = "asia-northeast3"`
  - `gke_cluster_name = "gke-gitops-cluster"`
  - `gke_node_service_account_email = "gke-gitops-node@[PROJECT_ID].iam.gserviceaccount.com"`
  - `network_name = "gke-gitops-vpc"`
  - `subnet_name = "gke-gitops-subnet"`
- 상태: 완료
- 관련 이슈: `docs/08-troubleshooting.md`의 GKE SSD quota 및 disk size troubleshooting 해결 확인. GKE credentials와 node 상태 검증은 다음 단계에서 진행 필요.

### 2026-04-19 - GKE cluster status와 로컬 kubectl 준비

- 명령: `gcloud container clusters list --region asia-northeast3 --project [PROJECT_ID]`
- 기대 결과: `gke-gitops-cluster`가 `RUNNING` 상태이고 node 수가 `asia-northeast3-a`, `asia-northeast3-c`의 node pool 구성과 일치
- 실제 결과: `gke-gitops-cluster` `STATUS=RUNNING`, `NUM_NODES=2`
- 상태: 완료

- 명령: `gcloud container clusters get-credentials gke-gitops-cluster --region asia-northeast3 --project [PROJECT_ID]`
- 기대 결과: kubeconfig context 생성 후 `kubectl` 접근 가능
- 실제 결과: kubeconfig entry는 생성됐다. 최초 실행 시 로컬에 `gke-gcloud-auth-plugin`이 없다는 경고와 `kubectl` 미설치 문제가 있었으나, 로컬 도구 설치 후 다음 검증에서 `kubectl` 접근 성공 확인.
- 상태: 완료
- 관련 이슈: `docs/08-troubleshooting.md` — 로컬 `kubectl` 및 `gke-gcloud-auth-plugin` 누락 이슈 해결 확인

### 2026-04-19 - GKE node와 system pod 검증

- 명령: `kubectl get nodes`
- 기대 결과: Terraform으로 생성한 2개 node가 `Ready` 상태
- 실제 결과: node 2개가 모두 `Ready`, Kubernetes version은 `v1.35.1-gke.1396002`
- 상태: 완료

- 명령: `kubectl get pods -A`
- 기대 결과: GKE system pod가 `Running` 또는 정상 진행 상태
- 실제 결과: `gke-managed-cim`, `gmp-system`, `kube-system` namespace의 pod가 `Running` 상태로 확인됨
- 상태: 완료
- 관련 이슈: `docs/08-troubleshooting.md` — 로컬 `kubectl` 및 `gke-gcloud-auth-plugin` 누락 이슈 해결 확인

### 2026-04-19 - GKE node service account IAM 조회

- 명령: `terraform output -raw gke_node_service_account_email`
- 기대 결과: GKE node pool에 연결된 node service account email 확인
- 실제 결과: `gke-gitops-node@[PROJECT_ID].iam.gserviceaccount.com`
- 상태: 완료

- 명령: `gcloud projects get-iam-policy [PROJECT_ID] --flatten="bindings[].members" --filter="bindings.role=roles/container.defaultNodeServiceAccount AND bindings.members:serviceAccount:${NODE_SA}" --format="table(bindings.role,bindings.members)"`
- 기대 결과: GKE node service account에 project-level `roles/container.defaultNodeServiceAccount` 부여 확인
- 실제 결과: `roles/container.defaultNodeServiceAccount`가 `serviceAccount:gke-gitops-node@[PROJECT_ID].iam.gserviceaccount.com`에 부여됨
- 상태: 완료

- 명령: `gcloud artifacts repositories get-iam-policy gke-gitops-images --location=asia-northeast3 --project=[PROJECT_ID] --flatten="bindings[].members" --filter="bindings.role=roles/artifactregistry.reader AND bindings.members:serviceAccount:${NODE_SA}" --format="table(bindings.role,bindings.members)"`
- 기대 결과: GKE node service account에 Artifact Registry repository-scoped `roles/artifactregistry.reader` 부여 확인
- 실제 결과: `roles/artifactregistry.reader`가 `serviceAccount:gke-gitops-node@[PROJECT_ID].iam.gserviceaccount.com`에 부여됨
- 상태: 완료
- 다음 검증: 실제 Artifact Registry image를 `k8s/deployment.yaml`에 반영한 뒤 Pod 생성으로 image pull 성공 여부 확인

### 2026-04-19 - 수동 image build/push smoke test

- 명령: `gcloud auth configure-docker asia-northeast3-docker.pkg.dev`
- 기대 결과: Artifact Registry Docker credential helper 설정
- 실제 결과: Docker credential helper가 이미 정상 등록되어 있음
- 상태: 완료

- 명령: `docker build -t "${IMAGE}" ./app`
- 기대 결과: `app/` Docker image build 성공
- 실제 결과: `nginx:1.27-alpine` base image pull 후 image build 성공. Image tag: `asia-northeast3-docker.pkg.dev/[PROJECT_ID]/gke-gitops-images/sample-app:manual-20260419201633`
- 상태: 완료

- 명령: `docker push "${IMAGE}"`
- 기대 결과: Artifact Registry에 sample app image push 성공
- 실제 결과: `manual-20260419201633` push 성공. Digest `sha256:5dfd50c2beec17dcec619d841f492889224372037c1a58319a1b4fddcaf6e4a9`, size `2261`
- 상태: 완료
- 관련 이슈: `docs/08-troubleshooting.md` — 로컬 Docker 미설치 이슈 해결 확인
- 다음 검증: image URI를 `k8s/deployment.yaml`에 반영한 뒤 Pod 생성으로 GKE image pull 성공 여부 확인

### 2026-04-19 - sample app Deployment와 GKE image pull 검증

- 명령: `grep -n "image:" k8s/deployment.yaml`
- 기대 결과: `k8s/deployment.yaml`에 수동 push한 Artifact Registry image URI 반영
- 실제 결과: `image: "asia-northeast3-docker.pkg.dev/[PROJECT_ID]/gke-gitops-images/sample-app:manual-20260419201633"` 반영 확인
- 상태: 완료

- 명령: `kubectl apply -f k8s/deployment.yaml`
- 기대 결과: `sample-app` Deployment 생성 또는 갱신
- 실제 결과: `deployment.apps/sample-app created`
- 상태: 완료

- 명령: `kubectl rollout status deployment/sample-app`
- 기대 결과: Deployment rollout 성공
- 실제 결과: `deployment "sample-app" successfully rolled out`
- 상태: 완료

- 명령: `kubectl get deploy,pods`
- 기대 결과: Deployment available, pod `Running`
- 실제 결과: `deployment.apps/sample-app` `READY=2/2`, pod 2개 `1/1 Running`, restart `0`
- 상태: 완료

- 명령: `kubectl describe pod -l app=sample-app`
- 기대 결과: GKE node가 Artifact Registry image를 pull하고 container가 `Running`
- 실제 결과: 두 pod 모두 Image ID `asia-northeast3-docker.pkg.dev/[PROJECT_ID]/gke-gitops-images/sample-app@sha256:5dfd50c2beec17dcec619d841f492889224372037c1a58319a1b4fddcaf6e4a9`로 실행. Events에 `Successfully pulled image` 기록됨.
- 상태: 완료
- 다음 검증: `Service`, GCE Ingress, NEG/backend 상태, External IP HTTP 접근 확인

### 2026-04-19 - Service와 Ingress 초기 생성/NEG 확인

- 명령: `kubectl apply -f k8s/service.yaml`
- 기대 결과: `sample-app` Service 생성
- 실제 결과: `service/sample-app created`
- 상태: 완료

- 명령: `kubectl apply -f k8s/ingress.yaml`
- 기대 결과: host rule 없는 GCE Ingress 생성
- 실제 결과: `ingress.networking.k8s.io/sample-app created`
- 상태: 완료

- 명령: `kubectl get svc sample-app`
- 기대 결과: `sample-app` ClusterIP Service 확인
- 실제 결과: `TYPE=ClusterIP`, `CLUSTER-IP=10.30.7.71`, port `80/TCP`
- 상태: 완료

- 명령: `kubectl describe svc sample-app`
- 기대 결과: GCE Ingress용 NEG annotation/status 또는 backend 연결 근거 확인
- 실제 결과: `cloud.google.com/neg: {"ingress":true}` annotation이 자동 추가됨. selector `app=sample-app`, endpoints `10.20.1.6:80`, `10.20.1.5:80` 확인. 이후 `cloud.google.com/neg-status`와 `svcneg` 리소스 생성도 확인.
- 상태: 완료

- 명령: `kubectl get ingress sample-app`
- 기대 결과: Ingress class, host rule 제거 상태, external address 또는 provisioning 상태 확인
- 실제 결과: 최초 `spec.ingressClassName: gce`만 있을 때는 class `gce`로 보였지만 `ADDRESS`가 계속 비어 있었다. `kubernetes.io/ingress.class: "gce"` annotation으로 수정 후 `ADDRESS`가 할당됨. hosts `*`, port `80`.
- 상태: 완료

- 명령: `kubectl describe ingress sample-app`
- 기대 결과: `/` path가 `sample-app:http` backend로 연결되고 events에 오류가 없음
- 실제 결과: `kubernetes.io/ingress.class: gce` annotation 반영 후 `UrlMap`, `TargetProxy`, `ForwardingRule` 생성 event와 `IPChanged` event 확인. `ingress.kubernetes.io/backends`는 sample app backend와 default backend 모두 `HEALTHY`로 표시됨.
- 상태: 완료

- 명령: `gcloud compute forwarding-rules list --project [PROJECT_ID] --filter='name~k8s'`
- 기대 결과: GKE Ingress가 생성한 forwarding rule과 External IP 확인
- 실제 결과: forwarding rule `k8s2-fr-...sample-app...` 생성, port `80`, target HTTP proxy 연결 확인
- 상태: 완료

- 명령: `gcloud compute backend-services get-health [SAMPLE_APP_BACKEND_SERVICE] --global --project [PROJECT_ID]`
- 기대 결과: sample app backend endpoint가 `HEALTHY`
- 실제 결과: `asia-northeast3-a` NEG의 pod endpoints가 `HEALTHY`로 표시됨. `asia-northeast3-c` NEG는 생성됐으나 현재 sample app pod가 없어서 healthStatus가 비어 있음.
- 상태: 완료

- 명령: `kubectl port-forward deploy/sample-app 18080:80` 후 `curl -i http://127.0.0.1:18080/`
- 기대 결과: Pod 내부 HTTP 응답 확인
- 실제 결과: `HTTP/1.1 200 OK`, `Server: nginx/1.27.5`, placeholder HTML 응답 확인
- 상태: 완료

- 명령: `curl -i http://[INGRESS_IP]/`
- 기대 결과: External IP로 placeholder app 응답 확인
- 실제 결과: IP 할당 직후에는 `Empty reply from server` 또는 `Connection reset by peer`가 발생했으나, Load Balancer 전파 대기 후 `HTTP/1.1 200 OK`, `Via: 1.1 google`, placeholder HTML 응답 확인
- 상태: 완료
- 관련 이슈: `docs/08-troubleshooting.md` — GKE Ingress `ingressClassName` 단독 사용으로 ADDRESS 미할당

### 2026-04-19 - GitHub Actions WIF 수동 구성 1차

- 명령: `gcloud iam service-accounts create github-actions-deploy --project=[PROJECT_ID] --display-name="GitHub Actions deploy service account"`
- 기대 결과: GitHub Actions가 impersonation할 deploy service account 생성
- 실제 결과: `Created service account [github-actions-deploy].`
- 상태: 완료

- 명령: `gcloud artifacts repositories add-iam-policy-binding gke-gitops-images --location=asia-northeast3 --project=[PROJECT_ID] --member=serviceAccount:github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com --role=roles/artifactregistry.writer`
- 기대 결과: deploy service account에 Artifact Registry repository-scoped writer 권한 부여
- 실제 결과: repository IAM에 `roles/artifactregistry.writer` binding 추가됨
- 상태: 완료

- 명령: `gcloud iam workload-identity-pools create github-actions --project=[PROJECT_ID] --location=global --display-name="GitHub Actions"`
- 기대 결과: GitHub Actions용 Workload Identity Pool 생성
- 실제 결과: `Created workload identity pool [github-actions].` 이후 조회 결과 pool state는 `ACTIVE`
- 상태: 완료

- 명령: `gcloud iam workload-identity-pools providers create-oidc ... --attribute-mapping=... --attribute-condition=...`
- 기대 결과: GitHub repository OIDC token을 신뢰하는 Workload Identity Provider 생성
- 실제 결과: 실패. CLI paste 중 `--attribute-mapping`이 `--attribute-`와 `mapping=...`으로 줄바꿈되어 `unrecognized arguments: --attribute-` 발생. 이어서 `--attribute-condition=...`이 별도 shell 명령처럼 실행되어 `No such file or directory` 발생. 또한 `GITHUB_OWNER=OWNER`, `GITHUB_REPO=REPOSITORY` placeholder 값이 그대로 설정되어 있어 실제 repository binding 값이 아직 확정되지 않음.
- 상태: 실패
- 관련 이슈: `docs/08-troubleshooting.md` — WIF provider 생성 명령 줄바꿈 및 placeholder repo 값
- 다음 검증: 실제 GitHub `OWNER/REPOSITORY` 값을 확정한 뒤 provider 생성, service account `roles/iam.workloadIdentityUser` binding, GitHub variables/secrets 등록

### 2026-04-19 - GitHub Actions WIF 수동 구성 완료

- 명령: `gcloud iam workload-identity-pools providers create-oidc gke-gitops-pipeline ... --display-name="GitHub Actions" --attribute-mapping=... --attribute-condition="assertion.repository=='[OWNER]/[REPOSITORY]'"`
- 기대 결과: 실제 GitHub repository에 제한된 Workload Identity Provider 생성
- 실제 결과: `Created workload identity pool provider [gke-gitops-pipeline].`
- 상태: 완료

- 명령: `gcloud iam workload-identity-pools providers describe gke-gitops-pipeline --project=[PROJECT_ID] --location=global --workload-identity-pool=github-actions`
- 기대 결과: provider state `ACTIVE`, issuer URI와 repository condition 확인
- 실제 결과: provider name `projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/github-actions/providers/gke-gitops-pipeline`, state `ACTIVE`, issuer `https://token.actions.githubusercontent.com`, attribute condition `assertion.repository=='[OWNER]/[REPOSITORY]'`
- 상태: 완료

- 명령: `gcloud iam service-accounts add-iam-policy-binding github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com --role=roles/iam.workloadIdentityUser --member=principalSet://.../attribute.repository/[OWNER]/[REPOSITORY]`
- 기대 결과: GitHub repository principal이 deploy service account를 impersonate 가능
- 실제 결과: deploy service account IAM policy에 repository-scoped `roles/iam.workloadIdentityUser` binding 추가됨
- 상태: 완료

- 명령: deploy service account IAM policy와 Artifact Registry repository IAM policy 조회
- 기대 결과: deploy service account에 `roles/iam.workloadIdentityUser`, Artifact Registry writer 권한 확인
- 실제 결과: `roles/iam.workloadIdentityUser` principal binding과 `roles/artifactregistry.writer` service account binding 확인
- 상태: 완료
- 다음 검증: GitHub repository variables/secrets 등록 후 `workflow_dispatch` build-only, `main` push image push 확인

### 2026-04-19 - GitHub repository push와 Actions run #1

- 명령: `git push -u origin main`
- 기대 결과: GitHub repository `[OWNER]/[REPOSITORY]`의 `main` branch에 baseline commit push
- 실제 결과: commit `c28b5d1084c496897667321df6102090f9ad0150` push 완료. GitHub Actions workflow run #1 생성.
- 상태: 완료

- 확인: GitHub Actions run `Build GKE GitOps pipeline baseline #1`
- 기대 결과: `push` event에서 `build` job 성공 후 `push` job이 Artifact Registry에 image push
- 실제 결과: workflow run #1은 `Status Failure`, total duration 7s. `Build image` job이 exit code 1로 실패했고 `Push image` job은 실행되지 않음. GitHub repository variables/secrets 등록 전 push되어 `Validate workflow configuration` 단계에서 실패했을 가능성이 높음.
- 상태: 실패
- 관련 이슈: `docs/08-troubleshooting.md` — GitHub Actions initial push가 repository variables/secrets 등록 전 실패
- 다음 검증: GitHub Actions variables/secrets 등록 후 workflow run #1 rerun 또는 빈 commit push로 재검증

### 2026-04-19 - GitHub Actions CI image push 검증

- 명령: `git commit -m "Record GitHub Actions initial run"` 후 `git push`
- 기대 결과: GitHub repository `main` branch에 새 commit push, GitHub Actions CI 실행
- 실제 결과: commit `e3a889e3cf74ba0491c60436492a085fe3419f4f` push 완료
- 상태: 완료

- 명령: `gcloud artifacts docker images list asia-northeast3-docker.pkg.dev/[PROJECT_ID]/gke-gitops-images/sample-app --include-tags`
- 기대 결과: GitHub Actions `main` push workflow가 Artifact Registry에 `sample-app:${GITHUB_SHA}` image를 push
- 실제 결과: Artifact Registry에 tag `e3a889e3cf74ba0491c60436492a085fe3419f4f` image 생성 확인. Digest `sha256:5612a9a865a5037fbf4c0a3f742251ed54d54f9396d2e517544f000efcb3c001`, create time `2026-04-19T21:20:18`, size `20972226`.
- 상태: 완료

- 참고: 기존 수동 push tag `manual-20260419201633`도 repository에 유지됨.
- 후속 검증: `k8s/deployment.yaml` image를 CI tag로 수동 갱신했고, 아래 Argo CD 검증에서 Git desired state sync와 rollout을 확인
- 공개 repo 정리: 검증 완료 후 `k8s/deployment.yaml`의 image는 account-specific URI 대신 placeholder로 복원한다. 실제 검증 image tag와 결과는 이 문서와 `docs/images/` 증거로 유지한다.

### 2026-04-19 - Argo CD 설치와 GitOps sync 검증

- 명령: `kubectl create namespace argocd`
- 기대 결과: Argo CD 설치 namespace 생성
- 실제 결과: `namespace/argocd created`
- 상태: 완료

- 명령: `kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
- 기대 결과: Argo CD CRD와 controller/server/repo-server 리소스 생성
- 실제 결과: 대부분의 리소스는 생성됐지만 `applicationsets.argoproj.io` CRD에서 `metadata.annotations: Too long` 오류 발생
- 상태: 실패 후 해결
- 관련 이슈: `docs/08-troubleshooting.md` — Argo CD install CRD annotation too long

- 명령: `kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
- 기대 결과: 대형 CRD를 server-side apply로 적용
- 실제 결과: Argo CD CRD, RBAC, service, deployment, statefulset, networkpolicy 리소스 server-side apply 완료
- 상태: 완료

- 명령: `kubectl -n argocd get pods`, `kubectl -n argocd rollout status deployment/argocd-server`, `deployment/argocd-repo-server`, `statefulset/argocd-application-controller`
- 기대 결과: Argo CD 핵심 pod와 controller rollout 완료
- 실제 결과: Argo CD pod 7개 모두 `Running`. `argocd-server`, `argocd-repo-server`, `argocd-application-controller` rollout 완료
- 상태: 완료

- 명령: `kubectl apply -f gitops/argocd-app.yaml`
- 기대 결과: Argo CD Application 생성
- 실제 결과: `application.argoproj.io/gke-gitops-pipeline created`
- 상태: 완료

- 명령: `kubectl -n argocd get application gke-gitops-pipeline`
- 기대 결과: `Synced/Healthy`
- 실제 결과: 최초에는 `OutOfSync/Healthy`, 이후 `Synced/Progressing`. Operation phase는 `Succeeded`, resource status는 Service/Deployment/Ingress 모두 `Synced`
- 상태: 부분 완료

- 명령: `kubectl get deploy,rs,pods -o wide`, `kubectl get events --sort-by=.lastTimestamp`
- 기대 결과: sample app Deployment가 CI image tag로 rollout 완료
- 실제 결과: 새 CI image ReplicaSet pod가 `Pending`, event `0/2 nodes are available: 2 Insufficient cpu`. 기본 rolling update surge로 3번째 pod를 만들 수 없어 rollout이 멈춤.
- 상태: 실패 후 해결
- 관련 이슈: `docs/08-troubleshooting.md` — Argo CD sync 후 Deployment rollout Pending

- 변경: `k8s/deployment.yaml`에 `strategy.rollingUpdate.maxSurge: 0`, `maxUnavailable: 1` 추가 후 commit `13572bdb7928e7bd59393738091bd925e06b1163` push. Argo CD hard refresh 실행.
- 기대 결과: 추가 surge pod 없이 rolling update 진행
- 실제 결과: Argo CD Application `Synced/Healthy`, revision `13572bdb7928e7bd59393738091bd925e06b1163`. Deployment `sample-app` rollout 성공, `READY=2/2`, `UP-TO-DATE=2`, `AVAILABLE=2`, new ReplicaSet `sample-app-64b9966587` `2/2 Ready`. Image `sample-app:e3a889e3cf74ba0491c60436492a085fe3419f4f`로 실행.
- 상태: 완료

- 명령: `curl -i http://[INGRESS_IP]/`
- 기대 결과: GitOps sync 후에도 External IP에서 placeholder app 응답
- 실제 결과: `HTTP/1.1 200 OK`, `Via: 1.1 google`, placeholder HTML 응답 확인
- 상태: 완료

## 증거 기록 기준

- 공개 가능한 출력만 기록한다.
- project ID, account, token, credential, private endpoint 등 민감한 값은 마스킹한다.
- 긴 로그는 붙이지 않고 핵심 결과와 캡처/링크 위치만 기록한다.
- 실패한 검증은 이 문서에 `실패`로 남기고, 원인 분석과 해결 과정은 `docs/08-troubleshooting.md`에 작성한다.
