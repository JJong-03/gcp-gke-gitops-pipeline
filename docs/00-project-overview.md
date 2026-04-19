# Project Overview

이 문서는 `gcp-gke-gitops-pipeline` 프로젝트의 목적, 범위, 기술 스택, 최종 산출물을 정리하는 상위 개요 문서다.

`README.md`가 외부 방문자를 위한 요약이라면, 이 문서는 이후 구현과 세부 문서가 따라야 할 프로젝트 기준선을 제공한다. 세부 구현 방법은 각 영역 문서로 넘기고, 여기서는 무엇을 만들고 무엇을 만들지 않을지를 명확히 한다.

## 프로젝트 요약

Terraform으로 GCP 기반 GKE 인프라를 구성하고, GitHub Actions가 컨테이너 이미지를 빌드해 Artifact Registry에 푸시하며, Argo CD가 Git 저장소의 Kubernetes desired state를 GKE에 동기화하는 GitOps 포트폴리오 프로젝트다.

## 현재 저장소 상태

| 영역 | 현재 상태 |
|---|---|
| 저장소 가이드 | `README.md`, `CLAUDE.md`, `AGENTS.md` 작성 완료 |
| 문서 구조 | `docs/00`부터 `docs/09`까지 파일 구조 고정 |
| Terraform | `network`, `gke`, `artifact_registry` 모듈 구현 및 apply 완료. `project_services`, `github_wif` 모듈 코드 추가 및 validate 완료, 기존 수동 리소스 import와 post-import plan 검토 필요. |
| Application | `app/`에 Nginx 기반 placeholder 앱과 Dockerfile 존재 |
| Kubernetes | `k8s/`에 `Deployment`, `Service`, `Ingress` workload manifest 존재 |
| GitOps | `gitops/argocd-app.yaml`로 Argo CD `Application` manifest 분리 |
| CI | `.github/workflows/ci.yml`의 Docker build/push workflow 구현 및 GitHub Actions OIDC/WIF 기반 Artifact Registry push 검증 완료 |
| 검증 | Terraform init/validate/plan/apply 완료. GKE cluster는 `RUNNING`, node 수는 `2`로 확인됨. `kubectl get nodes`, `kubectl get pods -A`로 node와 system pod 상태 확인 완료. GKE node service account IAM policy 조회, 수동 Artifact Registry image push, Deployment rollout, GKE image pull, Service/NEG annotation, Ingress backend/events, Ingress External IP HTTP 200 응답, GitHub Actions CI image push, Argo CD sync/health 검증 완료. |

## In Scope

- GCP custom VPC와 GKE용 subnet
- Pod/Service secondary IP range를 사용하는 VPC-native GKE baseline
- regional GKE cluster와 `asia-northeast3-a`, `asia-northeast3-c` node location을 사용하는 별도 node pool
- GCP API enablement Terraform 관리 전환
- Artifact Registry Docker repository
- GitHub Actions OIDC/WIF GCP-side prerequisite Terraform 관리 전환
- 최소 샘플 앱 컨테이너 이미지
- Kubernetes `Deployment`, `Service`, `Ingress`
- Argo CD `Application` 기반 GitOps sync 구조
- GitHub Actions 기반 Docker image build/push
- 단계별 검증 결과와 troubleshooting 기록

## Out of Scope For Initial Version

- private cluster 고도화
- service mesh, Istio, multi-cluster 구조
- blue-green 또는 canary rollout
- 복잡한 secret backend
- Terraform remote backend 구성
- Cloud DNS, Managed Certificate, static IP, HTTPS 고정 구성
- GitHub repository secret 값을 Terraform state로 관리
- CI build 결과를 Kubernetes manifest에 자동 반영하는 image updater 구성
- 운영 환경 수준의 보안/관측성/비용 최적화 전체 구성

초기 버전은 포트폴리오용으로 설명 가능하고 재현 가능한 GKE GitOps 흐름을 만드는 데 집중한다.

## 초기 운영 기준

| 항목 | 초기 기준 |
|---|---|
| GCP API enablement | 초기 수동 활성화 완료. 현재 Terraform import 대상으로 전환 중 |
| GitHub Actions 인증 | GitHub OIDC와 Workload Identity Federation 수동 구성 완료. GCP-side prerequisite는 Terraform import 대상으로 전환 중, GitHub secrets는 수동 유지 |
| GKE cluster | regional cluster |
| GKE node locations | `asia-northeast3-a`, `asia-northeast3-c` |
| 노드 구성 | 비용 통제를 위해 최소 노드 구성부터 시작. node disk size를 명시적으로 낮게 설정해 SSD quota 소비를 제한한다. |
| GKE image pull IAM | 별도 node service account에 Artifact Registry repository-scoped reader 권한 부여 |
| Image tag 반영 | CI push 후 `k8s/deployment.yaml` image URI를 수동 갱신 |
| GitOps 배포 | 수동 갱신된 Git desired state를 Argo CD가 sync |
| Ingress 검증 | host rule 없이 External IP 기반 HTTP 접근 확인 |

## 주요 기술 스택

| 영역 | 기술 | 사용 이유 |
|---|---|---|
| Infrastructure as Code | Terraform | GCP 리소스를 모듈 단위로 재현 가능하게 관리 |
| Cloud platform | GCP | GKE, Artifact Registry, VPC 등 프로젝트 핵심 리소스 제공 |
| Container platform | GKE | Kubernetes workload 실행과 Ingress 기반 외부 접근 검증 |
| CI | GitHub Actions | 컨테이너 이미지 build/push 자동화 |
| Image registry | Artifact Registry | GKE에서 사용할 Docker image 저장 |
| CD/GitOps | Argo CD | Git 저장소의 Kubernetes manifest를 클러스터에 동기화 |

## 최종 산출물

| 구분 | 산출물 |
|---|---|
| Infrastructure | Terraform root module과 `project_services`, `network`, `gke`, `artifact_registry`, `github_wif` 하위 모듈 |
| Application | `app/` placeholder 앱과 Dockerfile |
| Kubernetes | `Deployment`, `Service`, `Ingress` manifest |
| GitOps | Argo CD `Application` manifest |
| CI | GitHub Actions image build/push workflow |
| Validation | Terraform, GKE, Kubernetes, CI, Artifact Registry, Argo CD 검증 기록 |
| Runbook | 처음부터 다시 따라 실행할 수 있는 `docs/10-reproduction-runbook.md` |
| Documentation | 프로젝트 개요, 아키텍처, 구현 계획, 검증, troubleshooting, 포트폴리오 노트 |

## 문서 사용 기준

- 이 문서는 프로젝트 범위와 산출물 기준을 정의한다.
- 아키텍처 상세는 `docs/01-architecture.md`에 작성한다.
- 단계별 작업 상태는 `docs/02-implementation-plan.md`에 작성한다.
- Terraform 상세는 `docs/03-terraform-plan.md`에 작성한다.
- 실제 실행 결과는 `docs/07-validation.md`에 작성한다.
- 아직 검증하지 않은 항목은 완료된 것처럼 작성하지 않는다.
