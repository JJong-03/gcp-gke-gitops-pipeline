# GCP GKE GitOps Pipeline (Terraform)

<div align="center">
  <img src="https://img.shields.io/badge/GCP-151515?style=for-the-badge&logo=googlecloud&logoColor=4285F4" alt="GCP" />
  <img src="https://img.shields.io/badge/GKE-151515?style=for-the-badge&logo=kubernetes&logoColor=326CE5" alt="GKE" />
  <img src="https://img.shields.io/badge/Terraform-151515?style=for-the-badge&logo=terraform&logoColor=7B42BC" alt="Terraform" />
  <img src="https://img.shields.io/badge/GitHub_Actions-151515?style=for-the-badge&logo=githubactions&logoColor=2088FF" alt="GitHub Actions" />
  <img src="https://img.shields.io/badge/Artifact_Registry-151515?style=for-the-badge&logo=googlecloud&logoColor=34A853" alt="Artifact Registry" />
  <img src="https://img.shields.io/badge/Argo_CD-151515?style=for-the-badge&logo=argo&logoColor=EF7B4D" alt="Argo CD" />
  <img src="https://img.shields.io/badge/Docker-151515?style=for-the-badge&logo=docker&logoColor=2496ED" alt="Docker" />
  <br/>
</div>

> **Terraform으로 GCP 기반 GKE 인프라를 모듈화하고, <br/>GitHub Actions는 컨테이너 이미지 빌드와 푸시를 담당하며, <br/>Argo CD는 Git 저장소의 Kubernetes 매니페스트를 GKE에 동기화하는 GitOps 포트폴리오 프로젝트입니다.**

---

## Overview

| 항목 | 내용 |
|---|---|
| 목표 | GCP 기반 GKE 플랫폼을 Terraform, CI, GitOps 흐름으로 구성하고 포트폴리오용 문서와 검증 절차를 정리 |
| 핵심 구성 | VPC/Subnet, GKE, Artifact Registry, Kubernetes Deployment/Service/Ingress, Argo CD Application, GitHub Actions |
| 대상 리전 | `asia-northeast3` |
| GKE cluster 전략 | regional cluster를 기준으로 하며, node pool은 `asia-northeast3-a`, `asia-northeast3-c` node location을 명시 |
| CI 역할 | GitHub Actions가 Docker image build와 Artifact Registry push를 담당 |
| CD 역할 | Argo CD가 Git의 `k8s/` desired state를 GKE에 sync |
| 현재 상태 | Terraform apply 완료, GKE cluster `RUNNING`, node 2개 `Ready`, system pod `Running`, 수동 Artifact Registry image push, Deployment rollout, GKE image pull, Service/NEG, GCE Ingress External IP, HTTP 200 응답, GitHub Actions CI image push 확인 완료 |

---

## Architecture

현재 저장소의 의도된 흐름은 다음과 같습니다.

```text
User
  -> External HTTP(S) Load Balancer
  -> GKE Ingress
  -> Kubernetes Service
  -> sample-app Pods

Developer
  -> GitHub Repository
  -> GitHub Actions
  -> Artifact Registry

GitHub Repository
  -> Argo CD
  -> GKE Cluster

Terraform
  -> VPC/Subnet
  -> GKE Cluster and Node Pool
  -> Artifact Registry
```

아키텍처 이미지는 아직 추가하지 않았습니다. 다이어그램을 추가할 경우 `docs/images/gcp-gke-gitops-architecture.png` 경로를 사용할 계획입니다.

---

## What I Built

- `terraform/` 루트 모듈에서 `network`, `gke`, `artifact_registry` 하위 모듈을 연결했습니다.
- `terraform/modules/network/`는 custom VPC, GKE subnet, Pod/Service secondary IP range를 정의합니다.
- `terraform/modules/gke/`는 regional GKE cluster, 별도 node pool, 명시적 node locations, GKE node service account, GKE 기본 node IAM role, Workload Identity 설정을 정의합니다.
- `terraform/modules/artifact_registry/`는 Docker image 저장용 Artifact Registry repository와 GKE node service account의 repository-scoped reader 권한을 정의합니다.
- `app/`에는 CI 빌드 검증을 위한 최소 Nginx 기반 placeholder 애플리케이션과 Dockerfile을 두었습니다.
- `k8s/`에는 workload용 `Deployment`, `Service`, `Ingress` 매니페스트를 구성했습니다.
- `gitops/`에는 Argo CD `Application` 매니페스트를 분리했습니다.
- `.github/workflows/ci.yml`은 Docker image build를 수행하고, `main` 브랜치 push 시 Artifact Registry push를 수행하도록 작성되어 있습니다.
- `docs/00`부터 `docs/09`까지 프로젝트 개요, 아키텍처, Terraform 계획, GitOps/CI/CD, 검증, 트러블슈팅, 포트폴리오 노트를 분리했습니다.

---

## Traffic Flow

### User Traffic

```text
Browser
  -> External HTTP(S) Load Balancer
  -> GKE Ingress (`k8s/ingress.yaml`)
  -> ClusterIP Service (`k8s/service.yaml`)
  -> Pods managed by Deployment (`k8s/deployment.yaml`)
  -> Nginx placeholder app
```

`k8s/ingress.yaml`은 `kubernetes.io/ingress.class: "gce"` annotation을 사용하므로, 실제 클러스터에 적용하면 GKE Ingress Controller가 Google Cloud External HTTP(S) Load Balancer 생성을 담당하는 구조입니다. 초기 검증은 별도 domain 없이 host rule을 제거하고 External IP 기반 HTTP 접근으로 확인합니다.

### CI Flow

```text
Pull Request, Manual Dispatch, or Push
  -> GitHub Actions (`.github/workflows/ci.yml`)
  -> Docker build from `app/`
  -> Artifact Registry push only on `main` branch push
```

GitHub Actions는 CI 역할만 담당합니다. `pull_request`와 `workflow_dispatch`는 Docker image build만 수행하고 Artifact Registry push는 하지 않습니다. `push` 이벤트가 `main` 브랜치에서 발생할 때만 push job이 실행됩니다. 현재 workflow는 Kubernetes manifest의 image tag를 자동으로 갱신하지 않으므로, 초기 버전에서는 push된 image URI를 `k8s/deployment.yaml`에 수동 반영한 뒤 Argo CD sync로 배포를 검증합니다.

### GitOps CD Flow

```text
Git repository
  -> Argo CD Application (`gitops/argocd-app.yaml`)
  -> watches `k8s/`
  -> syncs desired state to GKE
```

Argo CD는 CD 역할을 담당합니다. 현재 `repoURL`은 `https://github.com/JJong-03/gcp-gke-gitops-pipeline.git`로 실제 GitHub 저장소 주소를 사용합니다.

---

## Skills Demonstrated

- Terraform root/module composition and readable module interfaces
- GCP VPC, subnet, secondary IP range, GKE, Artifact Registry baseline 구성
- GKE Workload Identity를 고려한 cluster baseline 설계
- Kubernetes Deployment, Service, Ingress, Argo CD Application 매니페스트 구성
- GitHub Actions와 Artifact Registry를 이용한 container image CI 흐름 구성
- CI(GitHub Actions)와 CD(Argo CD)의 책임 분리
- 문서, 검증 계획, troubleshooting 기록을 포함한 포트폴리오형 저장소 구성

---

## Key Design Decisions

| 결정 | 이유 |
|---|---|
| Terraform을 `network`, `gke`, `artifact_registry` 모듈로 분리 | 포트폴리오 리뷰어가 리소스 책임과 module boundary를 쉽게 이해할 수 있도록 하기 위해 |
| GKE subnet에 Pod/Service secondary range 명시 | VPC-native GKE 구성을 전제로 Pod/Service IP 범위를 네트워크 설계 안에 포함하기 위해 |
| regional GKE와 `asia-northeast3-a/c` node location 사용 | 멀티존 배치를 명확히 하되 최소 노드 구성으로 비용을 통제하기 위해 |
| GKE node 전용 service account 사용 | 기본 Compute Engine service account에 의존하지 않고 GKE 기본 node 권한과 Artifact Registry image pull 권한을 명확히 설명하기 위해 |
| GitHub Actions를 CI로만 사용 | 빌드와 이미지 push 책임을 CI에 두고, 클러스터 동기화는 Argo CD가 담당하도록 분리하기 위해 |
| GitHub OIDC/WIF는 초기 수동 사전조건으로 유지 | 인증 자동화보다 GKE GitOps end-to-end 검증을 먼저 안정화하기 위해 |
| image tag는 초기 수동 manifest 갱신 | 자동 image updater 도입 전 CI와 GitOps 책임 분리를 단순하게 검증하기 위해 |
| Ingress는 host rule 없이 External IP로 검증 | 초기 버전에서 domain, Cloud DNS, 인증서 의존성을 제거하기 위해 |
| Argo CD Application을 `k8s/` 경로에 연결 | Git 저장소의 Kubernetes manifest를 desired state로 사용하는 GitOps 흐름을 명확히 하기 위해 |
| Deployment/Service/Ingress만 우선 구성 | 초기 버전에서는 설명 가능한 최소 Kubernetes 리소스로 외부 접근 흐름을 검증하기 위해 |
| placeholder 값을 명시적으로 유지 | 프로젝트 ID, registry, repository, host, credential 같은 계정별 값을 저장소에 고정하지 않기 위해 |

---

## Repository Structure

```text
gcp-gke-gitops-pipeline/
├─ README.md
├─ CLAUDE.md
├─ AGENTS.md
├─ .gitignore
├─ app/
│  ├─ README.md
│  ├─ Dockerfile
│  └─ index.html
├─ terraform/
│  ├─ main.tf
│  ├─ variables.tf
│  ├─ outputs.tf
│  ├─ terraform.tfvars.example
│  └─ modules/
│     ├─ network/
│     │  ├─ main.tf
│     │  ├─ variables.tf
│     │  └─ outputs.tf
│     ├─ gke/
│     │  ├─ main.tf
│     │  ├─ variables.tf
│     │  └─ outputs.tf
│     └─ artifact_registry/
│        ├─ main.tf
│        ├─ variables.tf
│        └─ outputs.tf
├─ k8s/
│  ├─ deployment.yaml
│  ├─ service.yaml
│  └─ ingress.yaml
├─ gitops/
│  └─ argocd-app.yaml
├─ .github/
│  └─ workflows/
│     └─ ci.yml
└─ docs/
   ├─ 00-project-overview.md
   ├─ 01-architecture.md
   ├─ 02-implementation-plan.md
   ├─ 03-terraform-plan.md
   ├─ 04-gke-bootstrap.md
   ├─ 05-app-deployment.md
   ├─ 06-gitops-cicd.md
   ├─ 07-validation.md
   ├─ 08-troubleshooting.md
   └─ 09-portfolio-notes.md
```

---

## Scope And Limitations

- 이 저장소는 포트폴리오/학습 목적의 GCP GKE GitOps 프로젝트입니다.
- credential, token, secret 값은 포함하지 않습니다. 현재 `k8s/deployment.yaml`에는 수동 검증에 사용한 Artifact Registry image URI가 반영되어 있으며, 공개용 정리 단계에서 placeholder 복원 여부를 결정합니다.
- Terraform remote backend는 아직 구성하지 않았고, 현재는 기본 local state 기준입니다.
- GCP `terraform apply`가 완료되어 VPC, subnet, Artifact Registry, GKE cluster, node pool, node service account, IAM binding이 생성되었습니다.
- GKE cluster는 CLI 기준 `RUNNING`, node 수 `2`로 확인됐고, `kubectl get nodes`에서 두 node 모두 `Ready` 상태로 확인됐습니다.
- GKE node IAM은 별도 node service account, project-level `roles/container.defaultNodeServiceAccount`, Artifact Registry repository-scoped `roles/artifactregistry.reader` 권한을 사용하는 전략으로 Terraform에 정의 및 적용되었으며, 실제 IAM policy 조회와 image pull 검증까지 완료됐습니다.
- External HTTP(S) Load Balancer는 Terraform에서 별도 생성하지 않고, GKE Ingress 적용 시 GKE Ingress Controller가 생성하는 흐름을 전제로 합니다.
- Cloud DNS, Managed Certificate, static IP, HTTPS 고정 구성은 아직 포함하지 않았습니다.
- Argo CD 설치/bootstrap 절차는 아직 검증하지 않았고, 현재는 Application manifest를 실제 repository URL로 갱신한 상태입니다.
- CI workflow는 image build/push 중심이며, 초기 image tag 반영은 수동 manifest 갱신으로 진행합니다. GitHub Actions가 push한 image tag를 `k8s/deployment.yaml`에 반영했으며, 자동 업데이트는 후순위입니다.
- GitHub Actions의 Google Cloud 인증은 GitHub OIDC와 Workload Identity Federation을 사용하되, 초기 버전에서는 Terraform 자동화가 아니라 사전 수동 조건으로 문서화합니다.
- 필요한 GCP API는 초기 버전에서 Terraform이 자동 활성화하지 않고, 배포 전 수동으로 활성화합니다.
- `docs/07-validation.md`는 Terraform apply 완료, GKE cluster `RUNNING`, GKE node/pod, GKE node IAM policy, 수동 Artifact Registry image push, Deployment rollout, GKE image pull, Service/NEG annotation, Ingress backend/events, Ingress External IP HTTP 접근, GitHub Actions CI image push까지 기록했으며, GitOps 검증 결과는 아직 완료되지 않았습니다.

---

## Validation Targets

아래 항목은 이 프로젝트가 실제 배포 단계에서 기록해야 할 검증 목표입니다. 현재 README는 수행된 검증으로 표시하지 않습니다.

- [x] 사전 GCP API 활성화 확인
- [ ] GitHub OIDC/Workload Identity Federation 사전 구성 확인
- [x] `terraform init`
- [x] `terraform validate`
- [x] `terraform plan`
- [x] `terraform apply`
- [x] GKE cluster `RUNNING` 상태 확인
- [x] `kubectl get nodes`
- [x] `kubectl get pods -A`
- [x] GKE node service account의 `roles/container.defaultNodeServiceAccount` 권한 확인
- [x] GKE node service account의 Artifact Registry reader 권한 확인
- [x] 수동 Artifact Registry image push 확인
- [x] GKE image pull 확인
- [x] sample app Deployment rollout 확인
- [ ] GCP Console 또는 CLI에서 VPC, subnet, GKE, Artifact Registry 확인
- [x] `kubectl get svc`
- [x] Service NEG annotation과 Ingress backend/events 확인
- [x] GKE Ingress external address와 HTTP access 확인
- [x] GitHub Actions workflow image push 확인
- [ ] Argo CD Application sync/health 확인

---

## Quick Start

1. 로컬 도구를 준비합니다.

```bash
gcloud --version
terraform version
kubectl version --client
gke-gcloud-auth-plugin --version
docker version
```

수동 image build/push smoke test를 진행하려면 `docker version`이 성공해야 합니다. Docker가 없는 환경에서는 로컬 Docker를 먼저 설치하거나 GitHub Actions WIF 구성을 먼저 완료해 CI에서 image build/push를 검증합니다.

2. Terraform 변수 파일을 준비합니다. 실제 값은 저장소에 커밋하지 않습니다.

```hcl
# terraform/terraform.tfvars
project_id            = "YOUR_GCP_PROJECT_ID"
region                = "asia-northeast3"
gke_node_locations    = ["asia-northeast3-a", "asia-northeast3-c"]
gke_node_disk_size_gb = 30
```

3. Terraform 구성을 확인합니다.

사전에 아래 GCP API를 활성화합니다.

```bash
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable serviceusage.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable iamcredentials.googleapis.com
gcloud services enable sts.googleapis.com
```

```bash
cd terraform
terraform init
terraform validate
terraform plan
```

4. 인프라 생성 후 GKE credentials를 가져옵니다.

```bash
gcloud container clusters get-credentials gke-gitops-cluster \
  --region asia-northeast3 \
  --project YOUR_GCP_PROJECT_ID
```

5. 실제 배포 전 placeholder를 교체합니다.

- `k8s/deployment.yaml`: Artifact Registry image URI와 tag
- `k8s/ingress.yaml`: host rule 없이 External IP 기반 검증
- `gitops/argocd-app.yaml`: 실제 GitHub repository URL
- `.github/workflows/ci.yml`: `PROJECT_ID`, `REGION`, `ARTIFACT_REGISTRY_REPOSITORY`
- GitHub repository secrets: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`

6. Argo CD를 사용하지 않는 초기 검증에서는 Kubernetes manifest를 수동 적용할 수 있습니다.

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

7. GitOps 검증 단계에서는 Argo CD 설치 후 `gitops/argocd-app.yaml`을 실제 repository 값으로 수정해 적용합니다.

---

## Documentation

| 문서 | 내용 |
|---|---|
| [Project Overview](docs/00-project-overview.md) | 프로젝트 목적, 범위, 기술 스택, 산출물 정리 |
| [Architecture](docs/01-architecture.md) | GCP, GKE, Terraform, CI/CD, GitOps 아키텍처 설명 |
| [Implementation Plan](docs/02-implementation-plan.md) | 단계별 진행 계획, 현재 상태, 다음 작업 관리 |
| [Terraform Plan](docs/03-terraform-plan.md) | Terraform 모듈 경계, 리소스 범위, 검증 계획 |
| [GKE Bootstrap](docs/04-gke-bootstrap.md) | GKE 생성 후 인증, 접속, 기본 점검 절차 |
| [App Deployment](docs/05-app-deployment.md) | 샘플 앱 이미지, Deployment/Service/Ingress 배포 절차 |
| [GitOps CI/CD](docs/06-gitops-cicd.md) | GitHub Actions, Artifact Registry, Argo CD 역할 분리 |
| [Validation](docs/07-validation.md) | Terraform, GKE, Kubernetes, CI, Argo CD 검증 체크리스트 |
| [Troubleshooting](docs/08-troubleshooting.md) | 문제 상황, 원인 분석, 해결 및 재발 방지 기록 |
| [Portfolio Notes](docs/09-portfolio-notes.md) | 포트폴리오 설명 포인트, 배운 점, 확장 아이디어 |
| [Claude Guidance](CLAUDE.md) | 프로젝트 목표, 아키텍처 원칙, 구현 순서, 검증 기준 |
| [Agent Guidance](AGENTS.md) | AI-assisted workflow 역할 분리와 작업 규칙 |

---

## Planned Improvements

- `docs/images/gcp-gke-gitops-architecture.png` 아키텍처 다이어그램 추가
- Terraform remote backend와 state 관리 전략 정리
- Cloud DNS, Managed Certificate, static IP 기반 HTTPS Ingress 구성 검토
- GitHub OIDC와 Workload Identity Federation 구성을 Terraform으로 자동화할지 검토
- CI build 결과 image tag 자동 반영 전략 검토
- Argo CD 설치/bootstrap 절차와 sync 검증 결과 문서화
- `docs/07-validation.md`에 실제 명령어 실행 결과와 검증 증거 기록
- `docs/08-troubleshooting.md`에 진행 중 발생한 의미 있는 문제와 해결 과정 기록

---

## Status

| 영역 | 현재 상태 |
|---|---|
| Repository guidance | `CLAUDE.md`, `AGENTS.md` 작성됨 |
| Documentation | `docs/00`~`docs/09` 구조 존재, 대부분 TODO 기반 초안 |
| Terraform | 모든 모듈 구현 완료 (network, gke, artifact_registry). node location, GKE node service account IAM, node disk size 명시적 설정 포함. init/validate/plan/apply 완료. |
| Kubernetes | Deployment rollout, Service 생성, host rule 없는 GCE Ingress 생성, Service NEG annotation, Ingress backend/events, External IP HTTP 200 응답 확인 완료. Argo CD Application sync 검증 필요 |
| Application | Nginx 기반 placeholder app 존재 |
| GitHub Actions | Docker build/push workflow template 존재. image URI 값은 GitHub repository variables 기반이며, `main` push에서 Artifact Registry image push 확인 완료 |
| GitOps | Argo CD Application manifest 존재, 실제 repo URL 반영 완료, bootstrap/sync 검증 필요 |
| Validation | Terraform apply, GKE cluster `RUNNING`, node 2개 `Ready`, system pod `Running`, GKE node IAM policy, 수동 Artifact Registry image push, Deployment rollout, GKE image pull, Service/NEG annotation, Ingress backend/events, External IP HTTP 200 응답, GitHub Actions CI image push 확인 기록 존재. GitOps 검증 필요 |

현재 저장소는 Terraform 모듈 구현, Kubernetes manifest, CI workflow, GitOps manifest가 준비되어 있고 Terraform apply, GKE bootstrap, GKE node IAM policy 확인, 수동 Artifact Registry image push, Deployment rollout, GKE image pull, Service/NEG annotation, Ingress backend/events, External IP HTTP 200 응답, GitHub Actions CI image push 확인까지 완료된 상태입니다. 다음 단계는 Argo CD GitOps sync 검증을 기록하는 것입니다.
