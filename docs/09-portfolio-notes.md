# Portfolio Notes

이 문서는 `gcp-gke-gitops-pipeline` 프로젝트를 과제 또는 포트폴리오로 제출할 때 사용할 설명 문서다. 단순 작업 기록이 아니라 리뷰어가 무엇을 설계했고, 무엇을 검증했고, 어떤 문제를 해결했는지 빠르게 파악할 수 있도록 정리한다.

실제 검증 세부 기록은 [Validation](07-validation.md), 문제 해결 과정은 [Troubleshooting](08-troubleshooting.md), 캡처 목록은 [Image Capture Checklist](images/README.md)와 [README Evidence](../README.md#evidence)를 기준으로 한다.

## Project Summary

GCP GKE GitOps Pipeline은 GCP 기반 Kubernetes 배포 흐름을 Terraform, GitHub Actions, Artifact Registry, Argo CD로 연결한 포트폴리오 프로젝트다. Terraform은 GCP API enablement, VPC, subnet, regional GKE cluster, node pool, node service account, Artifact Registry repository, GitHub Actions WIF prerequisite를 모듈 단위로 표현한다. GKE는 sample app workload를 실행하고, Artifact Registry는 GitHub Actions와 수동 검증에서 push한 Docker image를 저장한다. GitHub Actions는 CI로서 Docker image build와 Artifact Registry push를 담당하고, Argo CD는 CD로서 Git 저장소의 `k8s/` desired state를 GKE에 동기화한다.

## Architecture Highlights

- Terraform module boundary는 `project_services`, `network`, `gke`, `artifact_registry`, `github_wif`로 나누었다. `project_services`는 필요한 GCP API enablement를 관리하고, `network`는 custom VPC, GKE subnet, Pod/Service secondary range를 관리하고, `gke`는 regional cluster와 node pool, node service account, GKE node IAM을 관리하며, `artifact_registry`는 Docker repository와 GKE image pull reader IAM을 관리한다. `github_wif`는 GitHub Actions deploy service account와 WIF GCP-side prerequisite를 표현한다.
- GKE는 `asia-northeast3` regional cluster로 구성했다. node locations는 `asia-northeast3-a`, `asia-northeast3-c`이고, `node_count = 1`은 각 node location당 1개 node를 의미하므로 실제 초기 node 수는 2개로 검증됐다.
- 네트워크는 VPC-native GKE를 전제로 한다. subnet 안에 Pod secondary range와 Service secondary range를 명시해 Pod IP와 Service IP를 GCP 네트워크 설계에 포함했다.
- 사용자 트래픽은 GKE-managed GCE Ingress가 만든 External HTTP(S) Load Balancer에서 시작해 Kubernetes Service를 거쳐 sample app Pods로 전달된다.
- CI/CD 책임은 명확히 분리했다. GitHub Actions는 image build/push까지만 수행하고, Argo CD는 Git에 기록된 Kubernetes manifest를 cluster desired state로 sync한다.
- GKE node는 default Compute Engine service account에 의존하지 않고 별도 node service account를 사용한다. project-level `roles/container.defaultNodeServiceAccount`와 Artifact Registry repository-scoped `roles/artifactregistry.reader`를 확인했고, 실제 image pull까지 검증했다.

## What Was Validated

완료 표시는 실제 실행 결과 또는 캡처 근거가 있는 항목만 기준으로 한다. 상세 명령과 결과는 [docs/07-validation.md](07-validation.md)에 기록되어 있다.

| Area | Validated result |
|---|---|
| Terraform | `terraform init`, `terraform validate`, `terraform plan`, `terraform apply` 완료. 최종 apply에서 VPC, subnet, GKE, node pool, node service account, IAM binding, Artifact Registry repository 생성 성공 |
| GKE cluster | regional cluster `RUNNING`, node 2개 `Ready`, GKE system pods `Running` 확인 |
| Node IAM | 별도 GKE node service account에 `roles/container.defaultNodeServiceAccount`와 repository-scoped `roles/artifactregistry.reader` 부여 확인 |
| Artifact Registry | 수동 Docker image build/push 성공, GitHub Actions `main` push 기반 commit tag image push 성공 |
| Image pull | GKE Pods가 Artifact Registry image를 정상 pull했고 image digest 기반 실행 확인 |
| Kubernetes workload | sample app `Deployment` rollout 성공, replicas `2/2` available 확인 |
| Service and NEG | `ClusterIP` Service 생성, GKE Ingress용 NEG annotation/status와 service network endpoint group 확인 |
| Ingress | GCE Ingress External IP 할당, backend health 확인, External IP HTTP 접근에서 `HTTP/1.1 200 OK` 확인 |
| GitHub Actions | OIDC/WIF 수동 구성 후 `main` push workflow가 Artifact Registry image push까지 성공 |
| Bootstrap Terraformization | GCP API enablement(8개)와 GitHub Actions WIF prerequisite(5개 리소스) Terraform import 완료. post-import `terraform plan` `No changes.` 확인 |
| Argo CD | Argo CD 설치, Application 생성, `Synced/Healthy`, CI image tag 기반 Deployment rollout 확인 |

검증 캡처는 [docs/images/README.md](images/README.md)에 목록화되어 있고, README의 [Evidence](../README.md#evidence) 섹션에는 주요 캡처가 바로 보이도록 연결되어 있다.

## Troubleshooting Story

아래 사례는 포트폴리오나 면접에서 설명하기 좋은 실제 문제 해결 흐름이다. 자세한 로그와 재발 방지 기준은 [docs/08-troubleshooting.md](08-troubleshooting.md)에 남겨두었다.

| Problem | Cause | Resolution | Lesson |
|---|---|---|---|
| GKE regional cluster 생성 중 SSD quota 초과 | regional cluster 생성 과정에서 임시 default pool이 여러 zone에 disk를 만들며 `asia-northeast3` SSD quota를 초과했다. | node pool disk size를 30GB로 명시하고, cluster 임시 default pool disk size도 별도로 통제했다. 최종적으로 quota 내에서 `terraform apply`를 완료했다. | regional GKE는 최종 node 수뿐 아니라 생성 중 임시 리소스도 quota에 영향을 준다. apply 전 node locations, node count, disk size 조합을 계산해야 한다. |
| default pool disk size 10GB 적용 실패 | quota 절감을 위해 임시 default pool disk를 10GB로 낮췄지만, 선택된 GKE COS image의 최소 disk size가 12GB였다. | cluster `node_config.disk_size_gb`를 20GB로 상향했다. 20GB는 image 최소 크기를 넘고, 250GB SSD quota 안에서도 수용 가능했다. | 비용 절감 값도 플랫폼 최소 요구사항을 만족해야 한다. quota 절감과 image/runtime 최소 조건을 함께 검토해야 한다. |
| Terraform `project_id` 값에 줄바꿈 포함 | CLI `-var` 입력 또는 변수 값에 newline control character가 들어가 Google provider API URL과 service account 요청이 깨졌다. | `project_id`를 한 줄 문자열로 다시 전달해 `terraform apply`를 재실행했다. | `invalid control character`, 줄바꿈된 API URL, project ID regex 오류가 보이면 credential보다 입력값 형식을 먼저 의심한다. |
| GKE Ingress `ADDRESS` 미할당 | Ingress manifest에 `spec.ingressClassName: gce`만 사용했고, GKE Ingress Controller가 기대하는 `kubernetes.io/ingress.class: "gce"` annotation이 없었다. | annotation 기반으로 수정한 뒤 GKE load balancer events, forwarding rule, backend health, External IP HTTP 200을 확인했다. | GKE Ingress는 표준 `ingressClassName` 표시와 실제 controller 처리 조건이 다를 수 있다. `kubectl get ingress`의 `CLASS`만 보지 말고 events와 GCP LB 생성 여부를 함께 확인해야 한다. |
| Argo CD install CRD annotation size 오류 | 공식 install manifest를 client-side apply로 적용하면서 대형 CRD schema가 last-applied annotation 크기 제한을 초과했다. | 같은 manifest를 `kubectl apply --server-side --force-conflicts`로 재적용해 CRD와 controller 리소스를 설치했다. | CRD가 큰 도구는 server-side apply가 더 안정적이다. 실패 후 수동 삭제보다 같은 desired state를 올바른 apply 방식으로 재적용하는 편이 안전하다. |
| Argo CD sync 후 Deployment rollout `Progressing` | 2개 `e2-medium` node에서 기본 rolling update `maxSurge`가 추가 pod를 만들었고, Argo CD와 system workload가 있는 상태에서 CPU가 부족했다. | `maxSurge: 0`, `maxUnavailable: 1`을 명시해 추가 surge pod 없이 rollout되도록 조정했다. 이후 Argo CD `Synced/Healthy`, Deployment `2/2` rollout, HTTP 200을 재확인했다. | 작은 fixed-size cluster에서는 기본 rollout 전략도 리소스 부족을 만들 수 있다. 비용 통제형 baseline에서는 rollout strategy를 명시하는 것이 검증 가능성을 높인다. |

## Design Tradeoffs

- GitHub OIDC/WIF는 먼저 수동 구성으로 end-to-end 흐름을 검증한 뒤, GCP-side prerequisite만 Terraform import로 편입했다. 이 방식은 이미 검증된 리소스를 recreate하지 않고 state로 관리하면서, GitHub secret 값은 계속 Terraform state 밖에 두기 위한 선택이었다. post-import `terraform plan`은 `No changes.`로 확인했다.
- Image tag 자동 업데이트는 후순위로 두었다. 초기 버전에서는 GitHub Actions가 image를 push하고, 사람이 `k8s/deployment.yaml`의 image tag를 갱신한 뒤, Argo CD가 Git desired state를 sync하는 구조로 CI와 CD 책임 분리를 명확히 검증했다. 공개 repo에서는 GCP 계정별 image URI를 placeholder로 되돌렸고, 실제 검증 image는 validation 기록과 캡처로 분리했다.
- Argo CD `repoURL`은 실제 공개 GitHub repository URL을 유지한다. 이 값은 secret이 아니라 Argo CD sync 증거와 연결되는 공개 주소이며, fork하거나 재사용할 때는 본인 repository URL로 교체해야 한다.
- Cloud DNS, HTTPS, static IP는 초기 범위에서 제외했다. 먼저 host rule 없는 GCE Ingress External IP와 HTTP 200으로 Service -> Pods 경로와 GKE-managed load balancer 동작을 검증하고, 도메인과 인증서 의존성은 다음 단계 개선으로 남겼다.
- Terraform remote backend는 아직 구성하지 않았다. 현재는 개인 포트폴리오 검증 단계라 local state로 진행했고, 협업이나 장기 운영으로 확장할 경우 GCS backend, state locking, 접근 권한 정책을 별도 설계해야 한다.
- Regional GKE를 사용하되 node locations를 2개 zone으로 제한했다. 이는 멀티존 배치와 비용 통제를 동시에 설명하기 위한 선택이며, production 수준의 autoscaling 또는 고가용성 설계를 완성했다는 의미는 아니다.
- Kubernetes 리소스는 `Deployment`, `Service`, `Ingress`, Argo CD `Application` 중심으로 제한했다. sample app 자체보다 플랫폼 흐름 검증이 목표였기 때문에 복잡한 app logic, service mesh, advanced rollout controller는 초기 버전에서 제외했다.

## Portfolio Talking Points

- Terraform root module과 `project_services`, `network`, `gke`, `artifact_registry`, `github_wif` module boundary로 GCP 리소스 책임을 설명할 수 있다.
- Regional GKE에서 `node_locations = ["asia-northeast3-a", "asia-northeast3-c"]`, `node_count = 1` 조합이 실제 node 2개로 생성되는 동작을 검증했다.
- VPC-native GKE를 위해 Pod/Service secondary range를 subnet 설계에 포함했다.
- GKE node service account를 별도로 두고, GKE 기본 node role과 Artifact Registry reader 권한을 분리해 image pull 경로를 검증했다.
- GitHub Actions는 Artifact Registry image build/push를 담당하고, Argo CD는 Git desired state sync를 담당하도록 CI/CD 책임을 분리했다.
- GCE Ingress, Service, NEG, backend health, External IP HTTP 200까지 확인해 외부 트래픽 경로를 끝까지 검증했다.
- GitHub OIDC/WIF를 service account key 없이 구성해 GitHub Actions image push를 검증했고, 같은 GCP-side prerequisite를 Terraform 코드와 state에 편입한 뒤 post-import plan `No changes.`까지 확인했다.
- Argo CD Application이 `k8s/` manifest를 sync하고 `Synced/Healthy` 상태가 되는 것을 CLI와 UI 캡처로 확인했다.
- quota, GKE Ingress class, Argo CD CRD, rollout resource 부족 같은 실제 실패를 문서화하고 원인과 해결을 재현 가능하게 남겼다.

## Future Improvements

- Terraform state를 GCS remote backend로 이전하고, state locking과 state 접근 권한 정책을 함께 정리한다.
- HTTPS Ingress를 위해 static IP, Managed Certificate, Cloud DNS 구성을 추가한다.
- GitHub Actions가 push한 image tag를 manifest에 자동 반영하는 전략을 도입한다. 선택지는 CI가 PR을 생성하는 방식, Kustomize/Helm values 업데이트, Argo CD Image Updater 등이다.
- Argo CD `AppProject`, RBAC, repository access policy를 강화해 GitOps 운영 경계를 더 명확히 한다.
- 비용 정리와 재현성을 위해 Ingress/Argo CD 삭제, Terraform destroy, Artifact Registry image cleanup 절차를 문서화한다.
- GKE node autoscaling, resource requests/limits, PodDisruptionBudget, readiness/liveness probe를 추가해 운영 안정성 관점의 다음 단계를 설계한다.
- sample app Deployment는 placeholder 목적상 단순하게 유지했지만, 후속 단계에서는 pod/container `securityContext`, non-root 실행, read-only root filesystem 같은 hardening을 검토한다.
