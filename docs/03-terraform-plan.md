# Terraform Plan

이 문서는 Terraform으로 어떤 GCP 리소스를 어떤 모듈 경계로 관리하는지 정리하는 설계 기준 문서다.

실제 `terraform validate`, `plan`, `apply` 결과는 이 문서가 아니라 `docs/07-validation.md`에 기록한다. 이 문서는 Terraform 코드가 바뀔 때 모듈 책임, 변수, 출력, 보류 결정을 함께 갱신하는 기준으로 사용한다.

## 현재 모듈 구조

```text
terraform/
├─ main.tf
├─ variables.tf
├─ outputs.tf
├─ terraform.tfvars.example
└─ modules/
   ├─ network/
   │  ├─ main.tf
   │  ├─ variables.tf
   │  └─ outputs.tf
   ├─ gke/
   │  ├─ main.tf
   │  ├─ variables.tf
   │  └─ outputs.tf
   └─ artifact_registry/
      ├─ main.tf
      ├─ variables.tf
      └─ outputs.tf
```

## Root Module

`terraform/main.tf`는 provider 설정과 하위 모듈 연결만 담당한다.

| 연결 대상 | 전달 값 |
|---|---|
| `module.network` | project, region, VPC/subnet 이름, primary/secondary CIDR |
| `module.gke` | project, region, cluster name, network/subnetwork self link, secondary range name, node pool 설정, node locations, node service account ID |
| `module.artifact_registry` | project, region, repository ID, GKE node service account reader member |

Root module은 GCP 리소스의 세부 구현을 직접 많이 갖지 않고, 하위 모듈의 경계를 읽기 쉽게 연결하는 역할을 유지한다.

## 사전 수동 조건

초기 버전에서는 GitHub/GCP 계정 사전조건은 배포 전 수동 조건으로 두고, GKE node의 image pull IAM처럼 클러스터 리소스 경계에 가까운 항목만 Terraform에 포함한다.

| 항목 | 초기 기준 |
|---|---|
| GCP API enablement | 필요한 API를 `gcloud services enable`로 사전 활성화 |
| GitHub OIDC/WIF | GitHub Actions용 Workload Identity Federation을 사전 구성 |
| CI deploy service account | Artifact Registry push 권한을 가진 service account를 사전 준비 |
| GKE node image pull IAM | Terraform으로 별도 node service account, GKE 기본 node role, Artifact Registry reader IAM 구성 |

필요 API:

```text
compute.googleapis.com
container.googleapis.com
artifactregistry.googleapis.com
serviceusage.googleapis.com
cloudresourcemanager.googleapis.com
iam.googleapis.com
iamcredentials.googleapis.com
sts.googleapis.com
```

API 활성화, Workload Identity Provider, GitHub Actions deploy service account, deploy service account IAM binding을 Terraform으로 관리하는 것은 후순위 개선으로 둔다.

## `network` Module

역할: GKE cluster가 사용할 네트워크 기반을 만든다.

| 리소스 | 목적 |
|---|---|
| `google_compute_network.vpc` | auto subnet을 비활성화한 custom VPC |
| `google_compute_subnetwork.gke` | GKE node가 사용할 subnet |
| secondary range `pods` | GKE Pod IP range |
| secondary range `services` | GKE Service IP range |

현재 기본값:

| 변수 | 기본값 |
|---|---|
| `network_name` | `gke-gitops-vpc` |
| `subnet_name` | `gke-gitops-subnet` |
| `subnet_cidr` | `10.10.0.0/20` |
| `pods_secondary_cidr` | `10.20.0.0/16` |
| `services_secondary_cidr` | `10.30.0.0/20` |

## `gke` Module

역할: GKE cluster와 별도 node pool을 만든다.

| 구성 | 현재 기준 |
|---|---|
| Cluster location | `var.region`, 기본값 `asia-northeast3` |
| Default node pool | 제거 |
| Separate node pool | `${var.cluster_name}-node-pool` |
| Node count | `var.node_count`, root 기본값 `1`, 설정된 node location당 1개 |
| Machine type | `var.machine_type`, 기본값 `e2-medium` |
| Node disk size | `var.disk_size_gb`, root 기본값 `30`GB. SSD quota 소비를 낮추기 위해 명시적으로 설정한다. |
| Cluster node_config disk | cluster resource의 `node_config.disk_size_gb = 20`. regional cluster 생성 시 임시 default pool이 3개 zone에 1개씩 생성되며, 이 pool의 SSD 사용량을 20GB×3=60GB로 제한한다. 20GB는 GKE COS 이미지 최소 크기(12GB) 이상이고 250GB quota 내에 여유 있게 수용된다. |
| IP allocation | network module의 Pod/Service secondary range 사용 |
| Workload Identity | `${var.project_id}.svc.id.goog` |
| Release channel | `REGULAR` |
| Deletion protection | `false` |
| Node locations | `var.node_locations`, root 기본값 `asia-northeast3-a`, `asia-northeast3-c` |
| Node service account | `google_service_account.node`, root 기본 ID `gke-gitops-node` |
| Node service account IAM | project-level `roles/container.defaultNodeServiceAccount`를 Terraform으로 부여 |

현재 Terraform은 regional cluster를 유지하면서 node pool에 `node_locations = var.node_locations`를 명시한다. 기본값은 2개 zone이며 `node_count = 1`이므로 초기 예상 node 수는 zone별 1개, 총 2개다. 이는 3개 zone 전체 사용보다 비용을 제한하면서 regional GKE 구조를 설명하기 위한 기준이다.

GKE node는 default Compute Engine service account 대신 별도 node service account를 사용한다. `terraform/modules/gke`는 이 service account에 project-level `roles/container.defaultNodeServiceAccount`를 부여하도록 정의하고, Artifact Registry repository 단위 reader 권한은 `terraform/modules/artifact_registry`가 관리한다. 실제 IAM 적용, policy 조회, GKE image pull 검증은 완료됐다.

## `artifact_registry` Module

역할: GitHub Actions가 push할 Docker image 저장소를 만든다.

| 구성 | 현재 기준 |
|---|---|
| Resource | `google_artifact_registry_repository.docker` |
| Format | `DOCKER` |
| Location | `var.region` |
| Repository ID | `gke-gitops-images` 기본값 |
| Reader IAM | GKE node service account에 repository-scoped `roles/artifactregistry.reader` 부여 |

예상 image URI 형식:

```text
${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_REPOSITORY}/sample-app:${GITHUB_SHA}
```

## GKE Image Pull IAM Strategy

초기 버전은 별도 node service account 전략을 선택한다.

| 선택지 | 판단 |
|---|---|
| default Compute Engine service account 사용 | 단순하지만 기존 project 권한 상태에 의존하므로 재현성과 설명력이 낮음 |
| 별도 node service account 생성 후 필요한 IAM만 부여 | Terraform module boundary와 node/image pull 권한을 명확히 보여줄 수 있어 초기 전략으로 선택 |

구현 기준:

- `terraform/modules/gke`가 node service account를 생성한다.
- `terraform/modules/gke`가 custom node service account에 project-level `roles/container.defaultNodeServiceAccount`를 부여한다.
- `google_container_node_pool`의 `node_config.service_account`가 해당 service account email을 사용한다.
- `terraform/modules/artifact_registry`가 해당 service account에 repository-scoped `roles/artifactregistry.reader`를 부여한다.
- project-wide reader 권한보다 repository scope를 우선한다.
- broad role이나 project-wide editor 권한은 사용하지 않는다.
- 실제 image pull 성공 여부는 Kubernetes 배포 단계에서 검증해야 하며, Terraform 코드 반영만으로 완료 처리하지 않는다. 2026-04-19 기준 수동 push image로 GKE image pull 검증을 완료했다.

## Root Outputs

| output | 목적 |
|---|---|
| `network_name` | 생성된 VPC 이름 확인 |
| `subnet_name` | 생성된 subnet 이름 확인 |
| `gke_cluster_name` | GKE credentials 획득과 검증에 사용 |
| `gke_cluster_location` | GKE credentials 획득과 검증에 사용 |
| `gke_node_service_account_email` | GKE node image pull IAM 확인에 사용 |
| `artifact_registry_repository_id` | CI image push 설정 확인 |

## 변수 관리 기준

- 실제 `project_id`는 `terraform.tfvars` 또는 CI 변수로 주입한다.
- `terraform.tfvars`는 커밋하지 않는다.
- `terraform/terraform.tfvars.example`에는 placeholder 값만 둔다.
- credential, token, service account key 같은 민감 값은 Terraform 변수나 문서에 직접 쓰지 않는다.

## 검증 계획

| 순서 | 명령 | 성공 기준 | 기록 위치 |
|---|---|---|---|
| 1 | `gcloud services enable ...` | `sts.googleapis.com` 포함 필요한 GCP API 활성화 성공 | `docs/07-validation.md` |
| 2 | `terraform init` | provider와 module 초기화 성공 | `docs/07-validation.md` |
| 3 | `terraform validate` | syntax와 provider schema 검증 성공 | `docs/07-validation.md` |
| 4 | `terraform plan` | 예상 리소스 diff 확인, 민감 값 노출 없음 | `docs/07-validation.md` |
| 5 | `terraform apply` | VPC, subnet, GKE, Artifact Registry 생성 성공 | `docs/07-validation.md` |
| 6 | GCP Console 또는 CLI 확인 | 생성 리소스가 Terraform 계획과 일치 | `docs/07-validation.md` |

## 보류 중인 Terraform 결정

| 항목 | 현재 상태 | 결정 기준 |
|---|---|---|
| Remote backend | 초기 범위 제외 | 포트폴리오 재현성을 해치지 않는 수준에서 필요할 때만 추가 |
| GKE private cluster | 초기 범위 제외 | 현재 목표는 설명 가능한 baseline GKE GitOps 흐름 |
| Managed certificate/static IP | 초기 범위 제외 | Ingress 기본 외부 접근 검증 후 필요 시 확장 |

## 구현 반영 상태

| 항목 | 결정 | 현재 상태 |
|---|---|---|
| Explicit node locations | regional GKE cluster의 node location은 `asia-northeast3-a`, `asia-northeast3-c` | root/module 변수, `google_container_node_pool.node_locations`, `terraform.tfvars.example` 반영됨. `terraform apply` 완료 후 GKE cluster `RUNNING`, `NUM_NODES=2`, node 2개 `Ready` 확인 |
| GKE node disk size | SSD quota 절감을 위해 `disk_size_gb` 변수를 root/module에 추가. node pool 기본값 30GB, cluster 임시 default pool 20GB | 2026-04-19 코드 반영 및 `terraform apply` 완료. cluster `node_config.disk_size_gb`를 10GB→20GB로 상향(GKE COS 이미지 최소 12GB 대응). 예상 최대 SSD: 임시 default pool 60GB(3×20) + node pool 60GB(2×30) = 120GB |
| GKE node service account IAM | 별도 node service account, project-level `roles/container.defaultNodeServiceAccount`, repository-scoped `roles/artifactregistry.reader` 사용 | Terraform 구현 및 apply 완료. `artifact_registry.reader_members`는 `map(string)` 기반으로 구현되어 apply-time unknown value를 정적 key `gke_node`로 전달. 실제 IAM policy 조회와 image pull 검증 완료 |
| API enablement | 초기 버전은 수동 사전조건 | Terraform 리소스 추가 없음. `sts.googleapis.com` 포함 API 활성화 결과를 validation 문서에 기록 완료 |
| GitHub OIDC/WIF | 초기 버전은 수동 사전조건 | Terraform 리소스 추가 없음. CI 문서에 prerequisite로 유지 |
