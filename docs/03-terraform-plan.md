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
   ├─ project_services/
   │  ├─ main.tf
   │  ├─ variables.tf
   │  └─ outputs.tf
   ├─ network/
   │  ├─ main.tf
   │  ├─ variables.tf
   │  └─ outputs.tf
   ├─ gke/
   │  ├─ main.tf
   │  ├─ variables.tf
   │  └─ outputs.tf
   ├─ artifact_registry/
   │  ├─ main.tf
   │  ├─ variables.tf
   │  └─ outputs.tf
   └─ github_wif/
      ├─ main.tf
      ├─ variables.tf
      └─ outputs.tf
```

## Root Module

`terraform/main.tf`는 provider 설정과 하위 모듈 연결만 담당한다.

| 연결 대상 | 전달 값 |
|---|---|
| `module.project_services` | project, enabled service set |
| `module.network` | project, region, VPC/subnet 이름, primary/secondary CIDR |
| `module.gke` | project, region, cluster name, network/subnetwork self link, secondary range name, node pool 설정, node locations, node service account ID |
| `module.artifact_registry` | project, region, repository ID, GKE node service account reader member |
| `module.github_wif` | project, project number, region, Artifact Registry repository ID, GitHub owner/repository, WIF pool/provider IDs, deploy service account ID |

Root module은 GCP 리소스의 세부 구현을 직접 많이 갖지 않고, 하위 모듈의 경계를 읽기 쉽게 연결하는 역할을 유지한다.

## Bootstrap Prerequisite Terraformization

초기 버전에서는 GitHub/GCP 계정 사전조건을 배포 전 수동 조건으로 두고, GKE node의 image pull IAM처럼 클러스터 리소스 경계에 가까운 항목만 Terraform에 포함했다. 현재 단계에서는 반복 가능한 GCP-side bootstrap prerequisite를 Terraform 코드로 표현하고, 기존 수동 생성 리소스를 import해서 recreate 없이 관리 대상으로 전환한다.

| 항목 | 현재 기준 |
|---|---|
| GCP API enablement | `project_services` module의 `google_project_service`로 관리. 기존 활성화 API는 import 필요 |
| GitHub OIDC/WIF | `github_wif` module로 deploy service account, WIF pool/provider, impersonation binding 관리. 기존 수동 리소스는 import 필요 |
| CI deploy service account | `github_wif` module에서 생성/관리. Artifact Registry writer 권한도 repository scope로 관리 |
| GKE node image pull IAM | Terraform으로 별도 node service account, GKE 기본 node role, Artifact Registry reader IAM 구성 |
| GitHub repository variables | 이번 코드 변경에서는 Terraform provider를 추가하지 않고 수동 유지 |
| GitHub repository secrets | Terraform state에 넣지 않고 수동 prerequisite로 유지 |

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

`serviceusage.googleapis.com` 자체도 Terraform 관리 대상에 포함하지만, 첫 bootstrap 시 Google provider가 Service Usage API에 접근할 수 있어야 한다. 현재 프로젝트는 수동 활성화가 완료되어 있으므로 import 후 plan 안정화를 우선한다.

## `project_services` Module

역할: 프로젝트에 필요한 GCP API enablement를 Terraform state로 관리한다.

| 리소스 | 목적 |
|---|---|
| `google_project_service.services` | `enabled_project_services`에 정의된 API를 활성화 상태로 관리 |

구현 기준:

- `for_each`는 service name set을 사용한다.
- `disable_on_destroy = false`를 고정해 Terraform cleanup 중 API가 자동 비활성화되지 않도록 한다.
- 기존에 수동 활성화된 API는 `terraform import`로 state에 편입한 뒤 plan을 확인한다.
- `network`, `artifact_registry`, `github_wif` module은 `project_services` 이후 생성되도록 root에서 의존성을 둔다.

현재 기본 API set:

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
| Cluster node_config lifecycle | `google_container_cluster.primary`에 `lifecycle { ignore_changes = [node_config] }` 적용. default node pool 삭제 후 GCP API가 cluster level node_config를 기본값으로 반환하여 매 plan마다 drift가 발생한다. 실제 workload node 설정은 `google_container_node_pool.primary`가 담당하므로 cluster level node_config는 변경 감지 대상에서 제외한다. |
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

## `github_wif` Module

역할: GitHub Actions가 service account key 없이 Artifact Registry에 image를 push할 수 있도록 GCP-side identity path를 관리한다.

| 리소스 | 목적 |
|---|---|
| `google_service_account.deploy` | GitHub Actions가 impersonation할 deploy service account |
| `google_artifact_registry_repository_iam_member.deploy_writer` | deploy service account에 repository-scoped `roles/artifactregistry.writer` 부여 |
| `google_iam_workload_identity_pool.github` | GitHub Actions OIDC identity를 받을 Workload Identity Pool |
| `google_iam_workload_identity_pool_provider.github` | GitHub OIDC issuer와 repository condition 정의 |
| `google_service_account_iam_member.github_workload_identity_user` | repository-scoped principal에 deploy service account impersonation 허용 |

Provider condition:

```text
assertion.repository=='[OWNER]/[REPOSITORY]'
```

Attribute mapping:

```text
google.subject=assertion.sub
attribute.repository=assertion.repository
attribute.repository_owner=assertion.repository_owner
attribute.actor=assertion.actor
```

Principal binding pattern:

```text
principalSet://iam.googleapis.com/projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/[POOL_ID]/attribute.repository/[OWNER]/[REPOSITORY]
```

기본 ID:

| 변수 | 기본값 |
|---|---|
| `wif_pool_id` | `github-actions` |
| `wif_provider_id` | `gke-gitops-pipeline` |
| `github_actions_deploy_service_account_id` | `github-actions-deploy` |

`project_number`, `github_owner`, `github_repository`는 repository별 값이므로 명시적으로 주입한다. GitHub repository secrets인 `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`는 Terraform output으로 식별자를 확인할 수 있지만, secret 등록 자체는 이번 단계에서 Terraform state 밖에 둔다.

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
| `enabled_project_services` | Terraform으로 관리하는 GCP API 목록 확인 |
| `github_actions_deploy_service_account_email` | GitHub Actions secret/manual 설정과 import 확인에 사용 |
| `github_actions_workload_identity_provider` | GitHub Actions WIF provider secret/manual 설정과 import 확인에 사용 |

## 변수 관리 기준

- 실제 `project_id`는 `terraform.tfvars` 또는 CI 변수로 주입한다.
- WIF import/plan에는 `project_number`, `github_owner`, `github_repository`가 추가로 필요하다.
- `terraform.tfvars`는 커밋하지 않는다.
- `terraform/terraform.tfvars.example`에는 placeholder 값만 둔다.
- credential, token, service account key 같은 민감 값은 Terraform 변수나 문서에 직접 쓰지 않는다.

## 검증 계획

| 순서 | 명령 | 성공 기준 | 기록 위치 |
|---|---|---|---|
| 1 | `terraform state list` | 기존 Terraform 관리 리소스 범위 확인 | `docs/07-validation.md` |
| 2 | `terraform init` | 신규 local module 등록과 provider 초기화 성공 | `docs/07-validation.md` |
| 3 | `terraform validate` | syntax와 provider schema 검증 성공 | `docs/07-validation.md` |
| 4 | `terraform import ...` | 기존 수동 API/WIF 리소스가 recreate 없이 state에 편입 | `docs/07-validation.md` |
| 5 | `terraform plan -var="project_id=..." -var="project_number=..." -var="github_owner=..." -var="github_repository=..."` | 예상치 못한 destroy/recreate 없음, 민감 값 노출 없음 | `docs/07-validation.md` |
| 6 | `terraform apply` | plan review 후에만 실행. import 안정화 전에는 실행하지 않음 | `docs/07-validation.md` |
| 7 | GCP Console 또는 CLI 확인 | 생성/관리 리소스가 Terraform 계획과 일치 | `docs/07-validation.md` |

## Import Strategy For Existing Bootstrap Resources

현재 API enablement와 GitHub Actions WIF prerequisite는 수동으로 생성 및 검증된 상태다. Terraform 코드 추가 후 바로 `apply`하면 중복 생성 또는 IAM drift가 발생할 수 있으므로 import를 먼저 실행한다.

GCP API enablement import pattern:

```bash
terraform import 'module.project_services.google_project_service.services["compute.googleapis.com"]' '[PROJECT_ID]/compute.googleapis.com'
terraform import 'module.project_services.google_project_service.services["container.googleapis.com"]' '[PROJECT_ID]/container.googleapis.com'
terraform import 'module.project_services.google_project_service.services["artifactregistry.googleapis.com"]' '[PROJECT_ID]/artifactregistry.googleapis.com'
terraform import 'module.project_services.google_project_service.services["serviceusage.googleapis.com"]' '[PROJECT_ID]/serviceusage.googleapis.com'
terraform import 'module.project_services.google_project_service.services["cloudresourcemanager.googleapis.com"]' '[PROJECT_ID]/cloudresourcemanager.googleapis.com'
terraform import 'module.project_services.google_project_service.services["iam.googleapis.com"]' '[PROJECT_ID]/iam.googleapis.com'
terraform import 'module.project_services.google_project_service.services["iamcredentials.googleapis.com"]' '[PROJECT_ID]/iamcredentials.googleapis.com'
terraform import 'module.project_services.google_project_service.services["sts.googleapis.com"]' '[PROJECT_ID]/sts.googleapis.com'
```

GitHub Actions WIF resource import patterns:

```bash
terraform import 'module.github_wif.google_service_account.deploy' 'projects/[PROJECT_ID]/serviceAccounts/github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com'
terraform import 'module.github_wif.google_iam_workload_identity_pool.github' 'projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/github-actions'
terraform import 'module.github_wif.google_iam_workload_identity_pool_provider.github' 'projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/github-actions/providers/gke-gitops-pipeline'
```

IAM member import IDs include the role and member string, so review them carefully before execution:

```bash
terraform import 'module.github_wif.google_artifact_registry_repository_iam_member.deploy_writer' 'projects/[PROJECT_ID]/locations/asia-northeast3/repositories/gke-gitops-images roles/artifactregistry.writer serviceAccount:github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com'

terraform import 'module.github_wif.google_service_account_iam_member.github_workload_identity_user' 'projects/[PROJECT_ID]/serviceAccounts/github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/github-actions/attribute.repository/[OWNER]/[REPOSITORY]'
```

Provider import ID 형식은 provider version에 따라 허용되는 축약형이 있을 수 있다. 이 문서는 명시형 resource name을 기준으로 하며, 실제 import 전에는 현재 provider 문서나 `terraform import` 오류 메시지로 최종 형식을 확인한다.

## 보류 중인 Terraform 결정

| 항목 | 현재 상태 | 결정 기준 |
|---|---|---|
| Remote backend | 초기 범위 제외 | 포트폴리오 재현성을 해치지 않는 수준에서 필요할 때만 추가 |
| GitHub repository variables Terraform화 | 이번 단계 제외 | GitHub provider와 token boundary가 추가되므로 별도 단계에서 결정 |
| GKE private cluster | 초기 범위 제외 | 현재 목표는 설명 가능한 baseline GKE GitOps 흐름 |
| Managed certificate/static IP | 초기 범위 제외 | Ingress 기본 외부 접근 검증 후 필요 시 확장 |

## 구현 반영 상태

| 항목 | 결정 | 현재 상태 |
|---|---|---|
| Explicit node locations | regional GKE cluster의 node location은 `asia-northeast3-a`, `asia-northeast3-c` | root/module 변수, `google_container_node_pool.node_locations`, `terraform.tfvars.example` 반영됨. `terraform apply` 완료 후 GKE cluster `RUNNING`, `NUM_NODES=2`, node 2개 `Ready` 확인 |
| GKE node disk size | SSD quota 절감을 위해 `disk_size_gb` 변수를 root/module에 추가. node pool 기본값 30GB, cluster 임시 default pool 20GB | 2026-04-19 코드 반영 및 `terraform apply` 완료. cluster `node_config.disk_size_gb`를 10GB→20GB로 상향(GKE COS 이미지 최소 12GB 대응). 예상 최대 SSD: 임시 default pool 60GB(3×20) + node pool 60GB(2×30) = 120GB |
| GKE node service account IAM | 별도 node service account, project-level `roles/container.defaultNodeServiceAccount`, repository-scoped `roles/artifactregistry.reader` 사용 | Terraform 구현 및 apply 완료. `artifact_registry.reader_members`는 `map(string)` 기반으로 구현되어 apply-time unknown value를 정적 key `gke_node`로 전달. 실제 IAM policy 조회와 image pull 검증 완료 |
| API enablement | `project_services` module로 Terraform 관리 대상 전환 | 코드 추가, 기존 8개 API import 완료. post-import `terraform plan` 결과 `No changes.` 확인 |
| GitHub OIDC/WIF | `github_wif` module로 GCP-side prerequisite Terraform 관리 대상 전환. GitHub secrets는 수동 유지 | 코드 추가, deploy service account/writer IAM/WIF pool·provider/workloadIdentityUser binding import 완료. post-import `terraform plan` 결과 `No changes.` 확인 |
