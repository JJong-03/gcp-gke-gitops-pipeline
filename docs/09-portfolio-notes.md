# Portfolio Notes

이 문서는 프로젝트를 포트폴리오로 설명할 때 사용할 요약 문장, 강조 역량, 설계 선택, 검증 근거, 개선 아이디어를 정리한다.

구현 계획을 대신하지 않으며, 실제 구현과 검증이 끝난 뒤 외부 설명용으로 다듬는 문서다.

## 작성 전제

현재 저장소는 Terraform 모듈 구현, Kubernetes manifest, GitHub Actions workflow, Argo CD Application manifest가 준비된 상태다. GCP `terraform apply`는 SSD quota와 disk size 이슈를 해결한 뒤 완료됐으며, GKE cluster는 `RUNNING`, node 수는 `2`, node 상태는 `Ready`, system pod는 `Running`으로 확인됐다. GKE node service account의 기본 node role과 Artifact Registry reader IAM policy 조회도 완료했고, 로컬 Docker 기반 수동 image build/push로 Artifact Registry에 sample app image를 push했다. 해당 image를 `k8s/deployment.yaml`에 반영해 Deployment rollout과 GKE image pull도 검증했다. Service 생성, NEG 자동 annotation, Ingress backend/events, External IP HTTP 200 응답까지 확인했다.

포트폴리오 설명 문장은 `docs/07-validation.md`의 실제 검증 결과와 `docs/08-troubleshooting.md`의 문제 해결 기록을 근거로 확정한다. 완료되지 않은 항목은 완료된 것처럼 표현하지 않는다.

## 최종 정리할 항목

| 항목 | 작성 기준 |
|---|---|
| 한 줄 요약 | Terraform, GKE, GitHub Actions, Artifact Registry, Argo CD 흐름을 짧게 설명 |
| 기술 스택별 역량 | 실제 구현 파일과 검증 결과에 근거해 작성 |
| 설계 선택 | 왜 module을 나눴는지, 왜 CI/CD 책임을 분리했는지 설명 |
| 검증 근거 | `docs/07-validation.md`에서 완료된 항목만 사용 |
| 문제 해결 경험 | `docs/08-troubleshooting.md`에 기록된 실제 이슈만 사용 |
| 한계와 개선 | 초기 범위 밖 항목을 다음 단계 개선으로 정리 |

## 현재 단계에서 사용할 수 있는 초안 문장

README 또는 면접 설명에 사용하기 전, 실제 검증 완료 여부에 맞게 표현을 조정한다.

짧은 설명:

```text
GCP 기반 GKE 인프라를 Terraform으로 구성하고, GitHub Actions와 Artifact Registry, Argo CD를 연결해 CI와 GitOps CD 책임을 분리하는 포트폴리오 프로젝트입니다.
```

현재 상태 설명:

```text
현재는 Terraform 모듈, Kubernetes workload manifest, Argo CD Application manifest, GitHub Actions workflow 초안이 준비되어 있고, Terraform apply, GKE bootstrap, GKE node IAM, 수동 Artifact Registry image push, Deployment rollout, GKE image pull, Service/NEG annotation, Ingress backend/events, External IP HTTP 200 응답 확인까지 완료했습니다. CI/GitOps 검증은 단계별로 추가하는 중입니다.
```

검증 완료 후 사용할 수 있는 설명은 실제 결과가 생긴 뒤 별도로 확정한다.

## 강조할 수 있는 설계 포인트

| 포인트 | 설명 기준 |
|---|---|
| Terraform module boundary | `network`, `gke`, `artifact_registry` 책임 분리 |
| VPC-native GKE baseline | subnet과 Pod/Service secondary range를 함께 설계 |
| GKE node disk size 명시 | SSD quota 제약 안에서 regional cluster가 안정적으로 생성되도록 임시 default pool과 실제 node pool 디스크 크기를 명시적으로 통제 |
| CI/CD 책임 분리 | GitHub Actions는 image build/push, Argo CD는 Git desired state sync |
| GitOps repository layout | `k8s/` workload manifest와 `gitops/` bootstrap manifest 분리 |
| 검증 중심 문서화 | 계획, 실행 결과, troubleshooting을 별도 문서로 관리 |
| 실제 장애 대응 기록 | `terraform apply` 중 발생한 quota 오류, GKE COS 이미지 disk 최소 크기 오류, 로컬 `kubectl`/auth plugin 누락, GKE Ingress class annotation 문제를 `docs/08-troubleshooting.md`에 기록 |

## 검증 후 보강할 내용

- Terraform apply 결과와 생성 리소스 요약은 README와 validation 문서에 반영됨
- GKE 접속, node/system pod, GKE node IAM policy 검증 결과는 validation 문서에 반영됨
- Kubernetes Deployment rollout과 GKE image pull 결과는 validation 문서에 반영됨
- Kubernetes Service/NEG annotation과 Ingress backend/events 결과는 validation 문서에 반영됨
- Ingress External IP HTTP 접근 검증 결과는 validation 문서에 반영됨
- GitHub Actions workflow 실행 결과
- 수동 Artifact Registry image push 결과는 validation 문서에 반영됨
- Argo CD sync/health 결과
- 실제 troubleshooting 사례와 해결 과정

## 이후 개선 아이디어

초기 버전 검증 후 필요에 따라 우선순위를 정한다.

| 개선 아이디어 | 현재 판단 |
|---|---|
| explicit node locations | Terraform에 반영됨, 실제 node placement 검증 후 포트폴리오 설명에 사용 |
| GKE image pull IAM | 별도 node service account와 repository-scoped reader IAM 구현, policy 조회, 실제 image pull 검증 완료 |
| GitOps image update strategy | 초기 수동 manifest 갱신 검증 후 자동 업데이트가 필요할 때 검토 |
| GitHub OIDC/WIF Terraform automation | 초기 수동 구성 검증 후 필요하면 Terraform 관리 대상으로 확장 |
| GCP API enablement Terraform automation | 초기 수동 활성화 검증 후 필요하면 Terraform 관리 대상으로 확장 |
| Managed Certificate/static IP/Cloud DNS | 외부 접근 검증 후 HTTPS 구성이 필요할 때 검토 |
| Terraform remote backend | 협업 또는 장기 관리 필요성이 생기면 검토 |
| 별도 namespace | `default` namespace 기준 검증 후 리소스 분리가 필요할 때 검토 |
