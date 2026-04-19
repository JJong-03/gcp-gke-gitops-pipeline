# Architecture

이 문서는 GCP, GKE, Terraform, GitHub Actions, Artifact Registry, Argo CD가 어떻게 연결되는지 설명하는 통합 아키텍처 문서다.

세부 명령어와 검증 결과보다 책임 경계, 트래픽 흐름, GitOps 흐름, Terraform 관리 범위를 명확히 하는 데 집중한다.

## 현재 아키텍처 기준

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
  -> GCP API enablement
  -> VPC/Subnet
  -> GKE Cluster and Node Pool
  -> Artifact Registry
  -> GitHub Actions deploy service account and WIF prerequisites
```

## 리전과 존 기준

| 항목 | 기준 |
|---|---|
| 대상 리전 | `asia-northeast3` |
| GKE cluster 전략 | regional cluster |
| node location 결정 | `asia-northeast3-a`, `asia-northeast3-c` |
| 비용 통제 기준 | 최소 노드 구성부터 시작. node disk size를 명시적으로 낮게 설정해 SSD quota 소비를 제한한다. |
| Node disk size | node pool 30GB, cluster 임시 default pool 20GB. 예상 최대 SSD 사용량 120GB로 250GB quota 내에서 운영. |
| 현재 구현 상태 | Terraform에 node location, disk_size_gb 변수와 node pool 설정 반영됨. `terraform apply` 완료 후 GKE cluster `RUNNING`, node 수 `2`, node `Ready`, system pod `Running` 확인. |

`gke_node_count = 1`은 설정된 각 node location당 1개 node를 의미한다. 기본 node location이 2개이므로 초기 예상 node 수는 2개이며, 3개 zone 전체 사용보다 비용을 제한하면서 regional cluster 구조를 설명하기 위한 기준이다.

## 사용자 트래픽 흐름

```text
Browser
  -> GKE-managed External HTTP(S) Load Balancer
  -> Ingress: k8s/ingress.yaml
  -> Service: k8s/service.yaml
  -> Pods: k8s/deployment.yaml
  -> Nginx placeholder app
```

현재 `k8s/ingress.yaml`은 `kubernetes.io/ingress.class: "gce"` annotation을 사용한다. GKE는 `ingressClassName`이 아니라 이 annotation을 기준으로 GKE Ingress Controller 처리 여부를 결정한다. External HTTP(S) Load Balancer는 Terraform에서 직접 생성하지 않고, GKE Ingress Controller가 Ingress 적용 이후 생성하는 흐름을 전제로 한다.

초기 버전의 Ingress 검증은 domain 없이 진행했다. `host` rule은 제거하고, GKE Ingress가 할당한 External IP로 HTTP 응답을 확인했다.

2026-04-19 기준 `Service`와 `Ingress`는 클러스터에 적용됐다. Service는 `ClusterIP`로 생성됐고 GKE가 `cloud.google.com/neg: {"ingress":true}` annotation을 자동 추가했다. Ingress는 host `*`, `/` path에서 `sample-app:http` backend로 연결됐으며, GKE-managed External HTTP(S) Load Balancer address와 HTTP 200 응답까지 확인했다.

## CI 흐름

```text
push / pull_request / workflow_dispatch
  -> GitHub Actions: .github/workflows/ci.yml
  -> Docker build from app/
  -> Artifact Registry push only on main branch push
```

GitHub Actions는 CI만 담당한다. 이미지 build와 Artifact Registry push는 workflow의 책임이지만, Kubernetes manifest를 클러스터에 직접 적용하지 않는다.

`pull_request`와 `workflow_dispatch`는 build-only 확인으로 사용한다. Artifact Registry push는 `.github/workflows/ci.yml`의 `push` job 조건에 따라 `main` branch `push` 이벤트에서만 실행된다.

초기 버전에서는 GitHub OIDC와 Workload Identity Federation을 수동 구성했고, `main` branch push 기반 Artifact Registry image push까지 검증했다. 현재 Terraformization 단계에서는 수동 구성된 GCP-side 인증 prerequisite를 Terraform 코드로 표현하고 import 후 관리 대상으로 전환하는 중이다. GitHub repository secrets 값은 Terraform state에 넣지 않고 수동 prerequisite로 유지한다.

## GitOps CD 흐름

```text
Git repository
  -> Argo CD Application: gitops/argocd-app.yaml
  -> watches path: k8s
  -> syncs Deployment, Service, Ingress to GKE
```

Argo CD는 CD와 desired state sync를 담당한다. 현재 `repoURL`은 `gitops/argocd-app.yaml`에서 실제 repository URL이 반영되어 있다.

초기 버전의 image tag 반영은 수동 manifest 갱신 방식이다. GitHub Actions가 Artifact Registry에 push한 image URI를 `k8s/deployment.yaml`에 반영한 뒤, Argo CD가 Git desired state를 sync하는 흐름을 `Synced/Healthy` 상태까지 검증했다. 자동 image update는 후순위 개선 사항이다.

## Terraform 관리 범위

| 모듈 | 관리 리소스 |
|---|---|
| `project_services` | GCP API enablement. `disable_on_destroy = false`로 cleanup 중 API 비활성화를 방지 |
| `network` | custom VPC, GKE subnet, Pod secondary range, Service secondary range |
| `gke` | GKE cluster, separate node pool, explicit node locations, node service account, project-level node IAM, Workload Identity baseline |
| `artifact_registry` | Docker image 저장용 Artifact Registry repository, GKE node service account의 repository-scoped reader IAM |
| `github_wif` | GitHub Actions deploy service account, Artifact Registry writer IAM, Workload Identity Pool/Provider, repository-scoped `roles/iam.workloadIdentityUser` binding |

Terraform은 Kubernetes workload manifest, Argo CD sync, GitHub Actions workflow 실행 결과를 직접 관리하지 않는다.

## GKE Node IAM And Artifact Registry Image Pull IAM

초기 버전의 GKE image pull 전략은 별도 node service account를 사용하는 방식이다.

| 항목 | 기준 |
|---|---|
| 선택한 전략 | 별도 GKE node service account 생성 |
| Terraform 위치 | `terraform/modules/gke`에서 service account 생성과 GKE 기본 node role 부여, `terraform/modules/artifact_registry`에서 repository-scoped reader IAM 부여 |
| GKE node 권한 | project-level `roles/container.defaultNodeServiceAccount` |
| Artifact Registry pull 권한 | repository-scoped `roles/artifactregistry.reader` |
| 선택 이유 | default Compute Engine service account의 기존 권한에 의존하지 않고, module boundary와 image pull 권한을 명확히 설명하기 위해 |

이 전략은 production hardening 전체를 목표로 하지 않는다. 초기 포트폴리오 범위에서는 custom node service account가 GKE node로 동작하는 데 필요한 기본 권한과 Artifact Registry image pull 권한 경계를 Terraform으로 명확히 드러내는 데 목적이 있다. 실제 IAM policy 조회와 GKE image pull 검증은 완료됐다.

## 주요 설계 결정

| 결정 | 이유 |
|---|---|
| Terraform module을 `network`, `gke`, `artifact_registry`로 분리 | GCP 리소스 책임을 포트폴리오 리뷰어가 쉽게 이해할 수 있도록 하기 위해 |
| regional GKE와 `asia-northeast3-a/c` node location 사용 | 멀티존 배치를 명확히 하되 최소 노드 구성으로 비용을 통제하기 위해 |
| node pool `disk_size_gb = 30`, cluster `node_config.disk_size_gb = 20` 명시 | asia-northeast3 SSD quota 250GB 내에서 regional cluster 생성이 가능하도록 임시 default pool(20GB×3)과 실제 node pool(30GB×2)의 SSD 합계를 약 120GB로 제한하기 위해 |
| 별도 GKE node service account 사용 | Artifact Registry image pull 권한을 default Compute Engine service account에 암묵적으로 의존하지 않기 위해 |
| GitHub Actions와 Argo CD 책임 분리 | CI는 이미지 생성/푸시, CD는 Git desired state sync로 역할을 명확히 하기 위해 |
| GitHub OIDC/WIF는 초기 수동 구성 후 Terraform import 대상으로 전환 | end-to-end 검증을 먼저 완료한 뒤, recreate 없이 GCP-side bootstrap prerequisite만 Terraform 관리로 옮기기 위해 |
| image tag는 초기 수동 manifest 갱신 | 자동 image updater 없이 CI build/push와 GitOps sync를 단순하게 검증하기 위해 |
| Ingress는 host rule 없이 External IP로 검증 | 초기 버전에서 domain, Cloud DNS, 인증서 의존성을 제거하기 위해 |
| `k8s/`에는 workload manifest만 유지 | Argo CD Application과 workload manifest의 책임을 분리하기 위해 |
| Argo CD Application은 `gitops/`에 분리 | GitOps bootstrap 리소스와 배포 대상 리소스를 구분하기 위해 |
| Deployment/Service/Ingress만 초기 범위에 포함 | 첫 버전에서 설명 가능하고 검증 가능한 최소 Kubernetes 흐름을 유지하기 위해 |

## 현재 제한 사항

- GCP 1차 `terraform apply` 중 GKE cluster 생성이 SSD quota 초과로 실패했고, 2차 시도에서는 임시 default pool disk 10GB가 GKE COS 이미지 최소 크기보다 작아 실패했다. 현재는 cluster 임시 default pool 20GB, node pool 30GB로 수정 후 `terraform apply`가 완료됐고 GKE cluster `RUNNING`, node `Ready`, system pod `Running`까지 확인했다. 자세한 내용은 `docs/08-troubleshooting.md` 참고.
- GKE node service account IAM은 Terraform에 정의 및 적용됐고, 실제 IAM policy 조회와 GKE image pull 검증도 완료됐다.
- Kubernetes Deployment rollout, pod `Running`, Service 생성, Service NEG 자동 annotation, Ingress backend/events, Ingress External IP, HTTP 200 응답까지 확인됐다.
- image tag를 Kubernetes manifest에 반영하는 초기 전략은 수동 manifest 갱신으로 결정되었으며, 자동화는 후순위다.
- Argo CD 설치/bootstrap, Application sync/health, CI image tag 기반 Deployment rollout까지 검증됐다.
- GCP API enablement와 GitHub Actions WIF prerequisite Terraform 코드는 추가됐지만, 기존 수동 리소스 import와 post-import plan 검토가 완료되기 전까지 적용 완료로 보지 않는다.
- 아키텍처 이미지는 `docs/images/00-architecture.png`에 추가되어 있으며, README는 이 이미지를 첫 번째 구조 설명으로 사용한다.
