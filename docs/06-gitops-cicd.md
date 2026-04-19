# GitOps CI/CD

이 문서는 GitHub Actions, Artifact Registry, Argo CD의 책임 경계를 정리한다.

핵심 원칙은 GitHub Actions가 CI image build/push를 담당하고, Argo CD가 Git desired state를 GKE에 동기화한다는 점이다. GitHub Actions가 Kubernetes manifest를 직접 apply하는 흐름은 초기 버전의 기준이 아니다.

## 책임 분리

| 영역 | 담당 | 책임 |
|---|---|---|
| CI | GitHub Actions | Docker image build, main branch push 시 Artifact Registry push |
| Image registry | Artifact Registry | sample app image 저장 |
| CD/GitOps | Argo CD | Git 저장소의 `k8s/` manifest를 GKE에 sync |
| Desired state | Git repository | `k8s/deployment.yaml`, `k8s/service.yaml`, `k8s/ingress.yaml` 관리 |

## GitHub Actions 기준

Workflow 파일:

```text
.github/workflows/ci.yml
```

Trigger:

| 이벤트 | 동작 |
|---|---|
| `pull_request` to `main` | Docker image build only |
| `workflow_dispatch` | Manual Docker image build only, no Artifact Registry push |
| `push` to `main` | Docker image build 후 Artifact Registry push |

현재 workflow job:

| job | 조건 | 역할 |
|---|---|---|
| `build` | 모든 trigger | `app/` 기준 Docker image build |
| `push` | `push` 이벤트이면서 `refs/heads/main` | Google Cloud 인증, Docker auth 설정, image rebuild, Artifact Registry push |

`workflow_dispatch`는 수동 smoke check 용도이며 build job만 실행한다. 현재 조건에서는 수동 실행이 Google Cloud 인증이나 Artifact Registry push까지 진행하지 않는다.

현재 workflow는 `main` branch push에서 image를 build/push하지만 Kubernetes manifest image tag를 자동 갱신하지 않는다. 초기 버전에서는 push된 image URI를 `k8s/deployment.yaml`에 수동으로 반영하고, 그 변경을 Git에 기록한 뒤 Argo CD sync로 배포를 검증했다.

2026-04-19 기준 GitHub Actions `main` push workflow로 Artifact Registry에 `sample-app:e3a889e3cf74ba0491c60436492a085fe3419f4f` image가 생성된 것을 확인했다. 이 tag를 GitOps desired state로 `k8s/deployment.yaml`에 수동 반영했고, Argo CD sync와 Deployment rollout까지 검증했다. 공개 repo 정리 후 `k8s/deployment.yaml`의 image는 계정별 Artifact Registry URI 대신 placeholder로 복원한다.

## Artifact Registry 기준

Terraform의 `artifact_registry` module이 Docker repository를 생성한다.

현재 기본 repository ID:

```text
gke-gitops-images
```

CI image URI 형식:

```text
${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_REPOSITORY}/sample-app:${GITHUB_SHA}
```

현재 `.github/workflows/ci.yml`은 GitHub repository variables를 기준으로 image URI를 만든다.

| GitHub repository variable | 값 |
|---|---|
| `GCP_PROJECT_ID` | GCP project ID |
| `GCP_REGION` | `asia-northeast3` |
| `ARTIFACT_REGISTRY_REPOSITORY` | `gke-gitops-images` |

`GCP_REGION`과 `ARTIFACT_REGISTRY_REPOSITORY`는 workflow에 기본값이 있지만, GitHub repository settings에 명시적으로 등록해 실행 로그와 설정을 더 쉽게 추적한다. `GCP_PROJECT_ID`는 반드시 등록해야 한다.

## 인증 기준

현재 workflow는 GitHub OIDC와 Google Cloud Workload Identity Federation을 사용한다. 이 구성은 수동으로 완료 및 검증됐고, Terraform 자동화는 후순위 개선으로 둔다.

| GitHub secret | 목적 |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | GitHub Actions가 사용할 Workload Identity Provider |
| `GCP_SERVICE_ACCOUNT` | Artifact Registry push 권한을 가진 service account |

secret 값 자체는 문서나 repository에 기록하지 않는다.

현재 workflow는 `google-github-actions/auth@v2`를 사용해 service account impersonation 방식의 Workload Identity Federation으로 인증한다. `push` job에는 GitHub OIDC token 요청을 위한 `permissions: id-token: write`와 repository checkout을 위한 `contents: read`가 설정되어 있다.

### GitHub OIDC/WIF 수동 구성 상태

| 항목 | 현재 확인 상태 |
|---|---|
| Workload Identity Pool/Provider | GitHub repository OIDC subject 조건에 맞게 수동 구성 완료 |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` secret | GitHub repository secret 등록 완료. 값은 `projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/[POOL_ID]/providers/[PROVIDER_ID]` 형식 |
| `GCP_SERVICE_ACCOUNT` secret | GitHub repository secret 등록 완료. 값은 `[SERVICE_ACCOUNT_NAME]@[PROJECT_ID].iam.gserviceaccount.com` 형식 |
| Service account impersonation | GitHub OIDC principal에 대상 service account의 `roles/iam.workloadIdentityUser` 부여 완료 |
| Repository principal binding | `principalSet://iam.googleapis.com/projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/[POOL_ID]/attribute.repository/[OWNER]/[REPOSITORY]` 형식으로 repository 단위 제한 완료 |
| Deploy service account push 권한 | Artifact Registry repository scope의 `roles/artifactregistry.writer` 부여 완료 |
| Secret 관리 | 실제 secret 값은 repository 파일, 문서, commit log에 기록하지 않음 |

Project 전체에 `roles/artifactregistry.writer`를 주는 방식은 설정이 단순하지만 권한 범위가 넓다. 초기 포트폴리오 프로젝트에서도 가능하면 Artifact Registry repository 단위 IAM binding을 우선 사용하고, project-wide 권한을 선택했다면 그 이유와 범위를 문서화한다.

2026-04-19 기준 deploy service account 생성, Artifact Registry repository-scoped writer 권한 부여, Workload Identity Pool/Provider 생성, repository-scoped `roles/iam.workloadIdentityUser` binding까지 완료됐다. Provider는 실제 GitHub repository 조건으로 제한되어 있다.

긴 `gcloud` 명령을 붙여넣을 때는 `--attribute-mapping` option을 중간에서 줄바꿈하지 않는다. 안전하게 실행하려면 attribute 값을 shell 변수로 분리한다.

```bash
ATTRIBUTE_MAPPING="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.actor=assertion.actor"
ATTRIBUTE_CONDITION="assertion.repository=='${GITHUB_OWNER}/${GITHUB_REPO}'"
```

문서화 가능한 식별자 형식:

| 값 | 예시 형식 |
|---|---|
| Workload Identity Provider resource name | `projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/[POOL_ID]/providers/[PROVIDER_ID]` |
| Deploy service account email | `github-actions-deploy@[PROJECT_ID].iam.gserviceaccount.com` |
| Repository principal | `principalSet://iam.googleapis.com/projects/[PROJECT_NUMBER]/locations/global/workloadIdentityPools/[POOL_ID]/attribute.repository/[OWNER]/[REPOSITORY]` |

WIF Terraform 자동화 후속 개선:

| 항목 | 상태 |
|---|---|
| Workload Identity Pool/Provider | 수동 구성 완료, Terraform 관리 미구현 |
| deploy service account | 수동 생성 완료, Terraform 관리 미구현 |
| IAM binding | 수동 구성 완료, Terraform 관리 미구현 |

## GKE Image Pull IAM 기준

GitHub Actions의 deploy service account는 Artifact Registry에 image를 push하는 주체이고, GKE node service account는 배포된 Pod의 image를 pull하는 주체다. 두 권한은 분리해서 관리한다.

| 주체 | 권한 | 범위 | 관리 방식 |
|---|---|---|---|
| GitHub Actions deploy service account | `roles/artifactregistry.writer` | repository scope | 수동 구성 및 검증 완료 |
| GKE node service account | `roles/container.defaultNodeServiceAccount` | project scope | Terraform 구현 |
| GKE node service account | `roles/artifactregistry.reader` | repository scope | Terraform 구현 |

GKE node service account는 `terraform/modules/gke`에서 생성하고, GKE 기본 node role도 같은 모듈에서 project-level IAM으로 부여한다. Artifact Registry reader IAM은 `terraform/modules/artifact_registry`에서 repository scope로 부여한다. 이 구현은 node 실행 권한과 image pull 경로를 명확히 하기 위한 초기 전략이다. 실제 IAM policy 조회와 GKE image pull 검증은 완료됐다.

## Argo CD 기준

Argo CD Application 파일:

```text
gitops/argocd-app.yaml
```

현재 설정:

| 항목 | 값 |
|---|---|
| Application name | `gke-gitops-pipeline` |
| Argo CD namespace | `argocd` |
| Source repoURL | 실제 공개 GitHub repository URL (`gitops/argocd-app.yaml`에서 관리, fork/reuse 시 교체) |
| Source path | `k8s` |
| Target namespace | `default` |
| Sync policy | automated prune/selfHeal |

Argo CD 설치와 cluster bootstrap은 검증됐다. `repoURL`은 실제 공개 GitHub repository URL로 유지하며, Application `gke-gitops-pipeline`은 revision `13572bdb7928e7bd59393738091bd925e06b1163` 기준 `Synced/Healthy` 상태를 확인했다. 이 값은 secret이 아니라 Argo CD가 이 repository를 sync했다는 공개 증거다. fork하거나 재사용할 때는 `repoURL`을 본인 repository URL로 교체해야 한다. CI image tag를 반영한 Deployment rollout도 `2/2` available 상태로 검증했다.

설치 중 `applicationsets.argoproj.io` CRD가 client-side apply annotation size 제한에 걸려 실패했으므로, 최종 설치는 server-side apply로 완료했다.

```bash
kubectl apply --server-side --force-conflicts \
  -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 후속 운영 결정

| 항목 | 현재 상태 | 선택지 |
|---|---|---|
| workflow env 관리 | repository variables 구성 완료 | GitHub Actions variables로 `GCP_PROJECT_ID`, `GCP_REGION`, `ARTIFACT_REGISTRY_REPOSITORY` 관리 유지 |
| Argo CD 설치 방식 | 공식 manifest를 server-side apply로 설치 완료 | Helm 전환은 필요 시 후순위 검토 |
| 배포 namespace | `default` 검증 완료 | 초기 버전 유지 또는 별도 namespace 도입 |

초기 버전에서는 과도한 자동화를 추가하지 않고, image build/push와 GitOps sync 책임 분리를 먼저 검증했다.

## 결정된 초기 전략

| 항목 | 결정 |
|---|---|
| image tag 반영 방식 | CI push 후 `k8s/deployment.yaml`을 수동 갱신 |
| GitOps 반영 | 수동 갱신된 manifest를 Git에 반영한 뒤 Argo CD sync/rollout 검증 완료 |
| Argo CD repoURL | 실제 공개 repository URL 유지, fork/reuse 시 교체 |
| 자동 업데이트 | CI PR 생성 또는 Argo CD Image Updater는 후속 개선 |
| Google Cloud 인증 | GitHub OIDC + Workload Identity Federation 수동 구성 및 검증 완료, Terraform 자동화는 후속 개선 |

## 실패 시 확인 위치

| 실패 영역 | 확인 위치 |
|---|---|
| Docker build 실패 | GitHub Actions `build` job log |
| Google Cloud 인증 실패 | GitHub Actions `push` job의 auth step |
| Artifact Registry push 실패 | Docker auth 설정, repository 위치, service account 권한 |
| Argo CD sync 실패 | Argo CD Application events, repoURL, path, manifest syntax |
| Kubernetes 적용 실패 | Argo CD sync message, `kubectl describe`, `kubectl get events` |

검증 결과는 `docs/07-validation.md`, 의미 있는 실패 분석은 `docs/08-troubleshooting.md`에 기록한다.
