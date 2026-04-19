# Implementation Plan

상태 기준일: 2026-04-19

이 문서는 프로젝트의 단계별 구현 순서, 현재 상태, 완료 기준, 다음 작업을 관리하는 진행판이다.

완성된 설명보다 작업 순서가 흔들리지 않게 하는 것이 목적이다. 실제 검증 결과는 이 문서에 길게 붙이지 않고 `docs/07-validation.md`에 기록한다.

## 상태 값

| 상태 | 의미 |
|---|---|
| 완료 | 구현 또는 문서 작업이 존재하고 현재 단계 기준으로 더 진행할 일이 없음 |
| 진행 중 | 초안이나 구현은 있으나 보강 또는 검증이 필요함 |
| 대기 | 앞 단계 완료 후 진행해야 함 |
| 보류 | 별도 결정이 필요함 |

## 단계별 구현 계획

| 단계 | 상태 | 작업 | 완료 기준 | 관련 문서 |
|---|---|---|---|---|
| 0 | 완료 | 저장소 가이드와 구조 기준 정리 | `README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/00~09` 구조가 존재함 | `README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/00-project-overview.md` |
| 1 | 완료 | 문서 기준선 확정 | `00`, `01`, `02`, `03`, `06`, `07`이 실제 구현 상태를 반영함 | `docs/00-project-overview.md`, `docs/01-architecture.md` |
| 2 | 완료 | Terraform 설계와 모듈 기준 확정 | root module과 `network`, `gke`, `artifact_registry` 모듈 책임/변수/출력이 문서화됨 | `docs/03-terraform-plan.md` |
| 3 | 완료 | Terraform 검증과 GCP 리소스 생성 | 사전 GCP API 활성화, `terraform init`, `validate`, `plan`, `apply` 결과가 기록됨. 3차 apply에서 GCP 리소스 생성 성공: `8 added, 0 changed, 0 destroyed`. | `docs/03-terraform-plan.md`, `docs/07-validation.md` |
| 4 | 완료 | GKE 접속과 bootstrap 점검 | `gcloud container clusters get-credentials`, `kubectl get nodes`, `kubectl get pods -A` 결과가 기록됨 | `docs/04-gke-bootstrap.md`, `docs/07-validation.md` |
| 5 | 완료 | 샘플 앱 이미지와 Kubernetes 배포 검증 | 실제 image URI가 수동 반영되고 `Deployment`, `Service`, host rule 없는 `Ingress`, Service NEG annotation/backend 상태, External IP 접근 결과가 기록됨 | `docs/05-app-deployment.md`, `docs/07-validation.md` |
| 6 | 진행 중 | GitHub Actions와 Artifact Registry 흐름 정리 | workflow trigger, image URI, GitHub OIDC/WIF 사전조건, secret, push 조건, 수동 image tag 반영 전략이 문서화됨 | `docs/06-gitops-cicd.md` |
| 7 | 대기 | Argo CD GitOps sync 검증 | `argocd-app.yaml` repoURL이 실제 값으로 교체되고 sync/health 결과가 기록됨 | `docs/06-gitops-cicd.md`, `docs/07-validation.md` |
| 8 | 대기 | 최종 검증, troubleshooting, 포트폴리오 정리 | 검증 증거와 해결 이슈를 기반으로 README와 portfolio notes가 정리됨 | `docs/08-troubleshooting.md`, `docs/09-portfolio-notes.md`, `README.md` |

## 현재 우선순위

1. **즉시**: GitHub OIDC/WIF prerequisite를 실제 repository 기준으로 구성하거나, 이미 구성됐다면 secret과 IAM binding을 확인한다.
2. GitHub Actions `workflow_dispatch`로 build-only 동작을 확인한다.
3. `main` branch push 기반 workflow에서 Artifact Registry image push를 검증한다.
4. 검증 결과를 `docs/07-validation.md`에 기록하고, 실패 시 `docs/08-troubleshooting.md`에 원인과 해결을 남긴다.

## 결정 완료 및 남은 검증

| 결정 항목 | 결정 | 다음 조치 | 같이 수정할 파일 |
|---|---|---|---|
| GKE node locations | regional cluster에 `asia-northeast3-a`, `asia-northeast3-c` 명시 | Terraform apply 완료, `kubectl get nodes`에서 node 2개 `Ready` 확인 완료 | `terraform/modules/gke/*`, `terraform/variables.tf`, `terraform/main.tf`, `README.md`, `CLAUDE.md`, `docs/01-architecture.md`, `docs/03-terraform-plan.md` |
| GKE node service account IAM | 별도 node service account 생성 후 project-level `roles/container.defaultNodeServiceAccount`와 Artifact Registry repository-scoped `roles/artifactregistry.reader` 부여 | Terraform apply, 실제 IAM policy 조회, GKE image pull 검증 완료 | `terraform/modules/gke/*`, `terraform/modules/artifact_registry/*`, `docs/03-terraform-plan.md`, `docs/05-app-deployment.md`, `docs/06-gitops-cicd.md` |
| GitHub Actions 인증 | GitHub OIDC + Workload Identity Federation 사용, 초기 버전은 수동 사전조건 | deploy service account, Artifact Registry writer binding, WIF pool/provider, repository-scoped `roles/iam.workloadIdentityUser` binding 완료. GitHub variables/secrets 등록 필요 | `.github/workflows/ci.yml`, `README.md`, `docs/06-gitops-cicd.md`, `docs/07-validation.md`, `docs/08-troubleshooting.md` |
| GCP API enablement | 초기 버전은 사전 수동 활성화 | `sts.googleapis.com` 포함 API 목록 문서화 및 실제 활성화 결과 기록 완료 | `README.md`, `docs/03-terraform-plan.md`, `docs/07-validation.md` |
| image tag 업데이트 전략 | 초기 버전은 CI push 후 수동 manifest 갱신, 이후 Argo CD sync | `sample-app:manual-20260419201633` image URI 수동 반영 완료. 자동 업데이트는 후순위로 유지 | `k8s/deployment.yaml`, `docs/05-app-deployment.md`, `docs/06-gitops-cicd.md` |
| 수동 image build/push | 로컬 Docker 기반 smoke test 또는 GitHub Actions WIF 기반 push 중 선택 | 로컬 Docker 기반 수동 smoke test 완료. `sample-app:manual-20260419201633` push, Deployment rollout, GKE pull 검증 완료 | `docs/05-app-deployment.md`, `docs/07-validation.md`, `docs/08-troubleshooting.md` |
| Ingress 검증 | 초기 버전은 host rule 제거, ClusterIP Service와 GCE Ingress baseline 유지 | Service 생성, NEG 자동 annotation, backend endpoint, Ingress backend/events, external address, HTTP 200 응답 확인 완료 | `k8s/ingress.yaml`, `k8s/service.yaml`, `README.md`, `docs/01-architecture.md`, `docs/05-app-deployment.md`, `docs/07-validation.md`, `docs/08-troubleshooting.md` |
| 실제 GitHub repository URL | `gitops/argocd-app.yaml`에 placeholder 유지 | 실제 repository 생성 후 repoURL 교체 | `gitops/argocd-app.yaml`, `README.md`, `docs/06-gitops-cicd.md` |

## 문서 업데이트 규칙

- 단계 상태가 바뀌면 이 문서를 먼저 갱신한다.
- Terraform 변경은 `docs/03-terraform-plan.md`와 함께 갱신한다.
- GKE 접속 절차 변경은 `docs/04-gke-bootstrap.md`와 함께 갱신한다.
- 앱 또는 Kubernetes manifest 변경은 `docs/05-app-deployment.md`와 함께 갱신한다.
- CI/CD 또는 Argo CD 변경은 `docs/06-gitops-cicd.md`와 함께 갱신한다.
- 실행 결과는 `docs/07-validation.md`에 기록하고, 실패 분석은 `docs/08-troubleshooting.md`에 연결한다.
