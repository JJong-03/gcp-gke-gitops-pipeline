# App Deployment

이 문서는 샘플 애플리케이션 이미지와 Kubernetes workload manifest를 기준으로 GKE 배포 흐름을 정리한다.

앱 기능 자체보다 GKE, Artifact Registry, Kubernetes, Argo CD 흐름을 검증할 수 있는 최소 workload를 유지하는 데 초점을 둔다.

## 현재 샘플 앱 기준

| 항목 | 현재 상태 |
|---|---|
| 위치 | `app/` |
| Runtime | Nginx placeholder |
| Docker base image | `nginx:1.27-alpine` |
| Endpoint | `/` |
| 목적 | 플랫폼 배포 흐름 검증용 placeholder |

## 이미지 기준

현재 CI workflow는 다음 형식의 image URI를 사용한다.

```text
${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_REPOSITORY}/sample-app:${GITHUB_SHA}
```

공개 repo의 `k8s/deployment.yaml` image 값은 계정별 Artifact Registry URI 노출을 피하기 위해 placeholder로 유지한다.

```text
your-region-docker.pkg.dev/your-project-id/your-repository-id/sample-app:tag
```

실제 검증에서는 GitHub Actions가 push한 다음 형식의 Artifact Registry image를 manifest에 임시 반영해 Argo CD sync와 rollout을 확인했다.

```text
asia-northeast3-docker.pkg.dev/[PROJECT_ID]/gke-gitops-images/sample-app:e3a889e3cf74ba0491c60436492a085fe3419f4f
```

초기 버전에서는 실제 배포 시 Artifact Registry에 push된 image URI를 `k8s/deployment.yaml`에 수동으로 반영한다. 자동 image updater나 CI 기반 manifest PR 생성은 후순위로 둔다.

수동 image build/push smoke test를 할 때는 로컬 Docker CLI와 Docker daemon이 필요하다.

```bash
docker version
gcloud auth configure-docker "${REGION}-docker.pkg.dev"
docker build -t "${IMAGE}" ./app
docker push "${IMAGE}"
```

2026-04-19 기준 최초 수동 smoke test는 로컬 `docker` 미설치로 `docker build` 단계에서 보류됐으나, Docker 준비 후 build/push를 완료했다. 확인된 수동 image tag는 아래와 같다.

```text
asia-northeast3-docker.pkg.dev/[PROJECT_ID]/gke-gitops-images/sample-app:manual-20260419201633
```

검증 당시 이 image URI를 `k8s/deployment.yaml`에 반영했고, GKE Pod 생성으로 image pull을 검증했다. 이후 GitHub Actions push workflow로 `sample-app:e3a889e3cf74ba0491c60436492a085fe3419f4f` image push를 검증했고, GitOps 검증을 위해 `k8s/deployment.yaml`의 image도 이 CI tag로 갱신했다. 공개 repo 정리 후 manifest는 placeholder로 복원했으며, 실제 검증 image와 증거는 `docs/07-validation.md`와 `docs/images/`에 남긴다. 자세한 troubleshooting 경과는 `docs/08-troubleshooting.md`에 기록한다.

## Kubernetes Manifest 기준

| 파일 | 역할 | 기준 |
|---|---|---|
| `k8s/deployment.yaml` | sample app Pod 관리 | `replicas: 2`, container port `80`, readiness/liveness probe `/`, resource request/limit 설정, 최소 노드 클러스터에 맞춘 rolling update `maxSurge: 0`, `maxUnavailable: 1` |
| `k8s/service.yaml` | cluster 내부 노출 | `ClusterIP`, port `80`, selector `app: sample-app`, manifest에는 명시적 NEG annotation 없음 |
| `k8s/ingress.yaml` | 외부 HTTP 접근 | host rule 없음, `kubernetes.io/ingress.class: "gce"` annotation 사용, path `/`가 `sample-app` Service의 `http` port로 연결 |

현재 baseline에서는 `k8s/service.yaml`에 `cloud.google.com/neg` annotation을 직접 추가하지 않는다. VPC-native GKE와 GCE Ingress 조합에서 NEG가 자동 구성되는지 실제 클러스터 적용 후 확인한다.

2026-04-19 기준 Service와 Ingress를 실제 클러스터에 적용했다. 최초 Ingress는 `spec.ingressClassName: gce`만 사용해 GKE controller가 처리하지 않았고 `ADDRESS`가 비어 있었다. GKE 공식 동작 기준에 맞춰 `kubernetes.io/ingress.class: "gce"` annotation으로 변경한 뒤 `loadbalancer-controller` sync event, external address 할당, backend `HEALTHY`, External IP HTTP 200 응답을 확인했다.

## 배포 방식

초기 smoke test와 최종 GitOps 흐름을 구분한다.

| 방식 | 사용 시점 | 기준 |
|---|---|---|
| 수동 `kubectl apply` | GKE 연결과 manifest 자체를 빠르게 확인할 때 | 임시 확인용이며 최종 CD 흐름으로 설명하지 않음 |
| Argo CD sync | GitOps 검증 단계 | `gitops/argocd-app.yaml`이 `k8s/` path를 sync |

최종 프로젝트 설명에서는 Argo CD가 CD 책임을 갖는 구조를 기준으로 한다.

## 배포 전 확인할 값

| 항목 | 현재 상태 | 조치 |
|---|---|---|
| Image URI | 공개 manifest는 placeholder 유지, 검증 당시 CI tag image로 Argo CD sync 완료 | 실제 배포 시 Artifact Registry image URI로 교체 |
| Ingress host | host rule 제거됨 | GKE Ingress가 할당한 External IP로 HTTP 접근 확인 |
| Argo CD repoURL | `gitops/argocd-app.yaml`에 실제 repository URL 반영 완료 | Argo CD Application 적용 |
| Namespace | `default` | 초기 버전에서는 유지 |

## Artifact Registry Image Pull 기준

실제 배포 시 GKE가 `k8s/deployment.yaml`에 반영된 Artifact Registry image를 pull할 수 있어야 한다. 초기 버전은 별도 GKE node service account를 사용하는 전략이다.

| 항목 | 기준 |
|---|---|
| Node identity | Terraform이 생성하는 별도 GKE node service account |
| GKE node 권한 | project-level `roles/container.defaultNodeServiceAccount` |
| Pull 권한 | Artifact Registry repository-scoped `roles/artifactregistry.reader` |
| 구현 위치 | `terraform/modules/gke`, `terraform/modules/artifact_registry` |
| IAM 조회 | 2026-04-19 기준 project IAM과 Artifact Registry repository IAM에서 확인 완료 |
| image pull 검증 | 2026-04-19 기준 Pod 생성과 `kubectl describe pod -l app=sample-app`에서 완료 |

image pull 실패가 발생하면 node service account email, `roles/container.defaultNodeServiceAccount` project IAM binding, Artifact Registry repository 위치, image URI, `roles/artifactregistry.reader` repository IAM binding을 함께 확인한다. IAM binding 조회와 실제 image pull 검증은 완료됐다.

## GCE Ingress And NEG 검증 포인트

초기 baseline은 ClusterIP Service와 GCE Ingress를 유지한다. 실제 적용 후에는 다음 항목을 완료 증거로 기록한다.

```bash
kubectl describe svc sample-app
kubectl describe ingress sample-app
```

확인할 내용:

- `kubectl describe svc sample-app`에서 NEG 관련 annotation 또는 status가 자동으로 붙었는지 확인한다.
- `kubectl describe ingress sample-app`에서 backend 연결 상태와 events를 확인한다.
- NEG 자동 구성이 확인되지 않거나 backend가 정상화되지 않으면, Service annotation 추가 여부는 검증 결과와 troubleshooting 기록을 근거로 판단한다.

현재 확인된 상태:

- Service: `ClusterIP`, `CLUSTER-IP=10.30.7.71`, port `80/TCP`
- Service NEG: `cloud.google.com/neg: {"ingress":true}` 자동 annotation 확인
- Service endpoints: `10.20.1.6:80`, `10.20.1.5:80`
- Ingress: `kubernetes.io/ingress.class: "gce"` annotation, hosts `*`, `/` path가 `sample-app:http`로 연결
- Ingress events: UrlMap, TargetProxy, ForwardingRule 생성과 IP 할당 확인
- Ingress backend: sample app backend `HEALTHY`
- Ingress external address: 할당 완료
- HTTP 접근: External IP에서 `HTTP/1.1 200 OK` 확인

## 검증 기준

| 확인 항목 | 기대 결과 | 기록 위치 |
|---|---|---|
| `kubectl get deploy` | `sample-app` deployment available | `docs/07-validation.md` |
| `kubectl get pods` | sample app pod가 `Running` | `docs/07-validation.md` |
| `kubectl get svc` | `sample-app` ClusterIP service 확인 | `docs/07-validation.md`에 완료 기록 |
| `kubectl describe svc sample-app` | Service의 NEG 관련 annotation/status 확인 | `docs/07-validation.md`에 완료 기록 |
| `kubectl get ingress` | external address 또는 provisioning 상태 확인 | `docs/07-validation.md`에 완료 기록 |
| `kubectl describe ingress sample-app` | Ingress events와 backend 상태 확인 | `docs/07-validation.md`에 backend/events 완료 기록 |
| HTTP 접근 | External IP로 placeholder app 응답 확인 | `docs/07-validation.md`에 완료 기록 |

실패 원인이 의미 있으면 `docs/08-troubleshooting.md`에 별도 기록한다.
