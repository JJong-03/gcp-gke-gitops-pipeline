# Image Capture Checklist

이 폴더는 과제/포트폴리오 제출용 검증 캡처를 보관한다.

민감한 값은 캡처하지 않는다. GitHub secrets 값, token, credential, 개인 계정 세부 정보는 화면에 노출하지 않는다. GitHub secret은 값이 아니라 secret name 목록만 보이도록 캡처한다.

## Current Captures

| File | Evidence |
|---|---|
| `00-architecture.png` | GCP GKE GitOps Pipeline architecture diagram |
| `01-terraform-apply-success.png` | `terraform apply` 성공과 Terraform outputs |
| `02-gke-cluster-running.png` | GKE cluster `RUNNING`, node 수 `2` |
| `03-gke-get-credentials.png` | `gcloud container clusters get-credentials` 성공 |
| `04-kubectl-nodes-system-pods.png` | `kubectl get nodes`, `kubectl get pods -A` |
| `05-gke-node-artifact-registry-iam.png` | GKE node service account IAM, Artifact Registry reader IAM |
| `06-sample-app-deployment-rollout-image-pull.png` | sample app Deployment rollout과 image pull 확인 |
| `07-ingress-address-pending-before-class-fix.png` | GKE Ingress class 이슈 전 `ADDRESS` 미할당 상태 |
| `08-github-actions-variables.png` | GitHub Actions repository variables 등록 |
| `09-github-actions-ci-success.png` | GitHub Actions workflow run 성공 |
| `10-artifact-registry-ci-image-tag.png` | Artifact Registry에 CI image tag 생성 확인 |
| `11-github-actions-run-detail-build-push.png` | 성공한 GitHub Actions run 상세 화면. `Build image`, `Push image` job 성공 |
| `12-github-actions-secrets-names.png` | GitHub Actions secrets 화면. secret 값 없이 secret name만 확인 |
| `13-ingress-external-ip-http-200.png` | Ingress external IP와 `HTTP/1.1 200 OK` 확인 |
| `14-argocd-application-synced-healthy-cli.png` | Argo CD Application CLI 조회 결과 `Synced`, `Healthy` |
| `15-argocd-rollout-ci-image.png` | CI image tag 기반 rollout, `READY=2/2`, pod `Running` |
| `16-argocd-ui-synced-healthy.png` | Argo CD UI Application resource tree, `Synced/Healthy` 상태 |
| `17-gcp-load-balancer-ingress-detail.png` | GCP Console Load Balancer 상세 화면. Ingress external IP와 backend 연결 확인 |
| `18-gcp-artifact-registry-console-tags.png` | GCP Console Artifact Registry image tags 화면. `manual-*`와 commit SHA tag 확인 |
| `19-gcp-vpc-subnet-secondary-ranges.png` | VPC subnet과 Pod/Service secondary IP range 확인 |

## Intentionally Omitted

| Item | Reason |
|---|---|
| `20-github-repository-files.png` | repository 구조는 캡처보다 tree 형식 텍스트로 문서/README에 넣는 편이 더 명확함 |
| `21-troubleshooting-docs.png` | troubleshooting 문서는 README 또는 제출 문서에서 링크로 연결하는 편이 더 적합함 |

## Capture Order Recommendation

1. GitHub Actions success detail
2. GitHub secrets names
3. Ingress external IP and HTTP 200
4. Argo CD Synced/Healthy
5. Deployment rollout with CI image
6. GCP Console Load Balancer and Artifact Registry
7. VPC/subnet secondary ranges
