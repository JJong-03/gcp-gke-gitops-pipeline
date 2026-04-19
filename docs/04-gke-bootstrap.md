# GKE Bootstrap

이 문서는 Terraform으로 GKE cluster를 만든 뒤 로컬 환경에서 cluster credentials를 가져오고 `kubectl`로 기본 상태를 점검하는 절차를 기록한다.

실제 실행 결과와 증거는 `docs/07-validation.md`에 기록하고, 접속 실패 원인 분석은 `docs/08-troubleshooting.md`에 기록한다.

## 전제 조건

| 항목 | 기준 |
|---|---|
| Terraform apply | GKE cluster와 node pool 생성 완료 |
| GCP project | 실제 project ID는 로컬 환경 변수나 `terraform.tfvars`에만 존재 |
| Region | 기본값 `asia-northeast3` |
| Cluster name | 기본값 `gke-gitops-cluster` |
| Local tools | `gcloud`, `kubectl`, `gke-gcloud-auth-plugin`, `terraform` 설치 |

## 로컬 도구 확인

GKE credentials를 가져오기 전에 로컬 CLI와 GKE 인증 plugin을 확인한다.

```bash
gcloud --version
kubectl version --client
gke-gcloud-auth-plugin --version
```

`kubectl` 또는 `gke-gcloud-auth-plugin`이 없으면 먼저 gcloud component 설치를 시도한다.

```bash
gcloud components install kubectl gke-gcloud-auth-plugin
```

`gcloud components`가 패키지 설치 방식 때문에 비활성화되어 있으면 apt 패키지로 설치한다.

```bash
sudo apt-get update
sudo apt-get install -y kubectl google-cloud-sdk-gke-gcloud-auth-plugin
```

환경에 따라 newer Google Cloud CLI 패키지명을 쓰는 경우 아래 패키지명이 필요할 수 있다.

```bash
sudo apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin
```

## 접속 절차

실제 값은 환경 변수로 주입해서 사용한다.

```bash
export PROJECT_ID="YOUR_GCP_PROJECT_ID"
export REGION="asia-northeast3"
export CLUSTER_NAME="gke-gitops-cluster"
```

GCP 계정과 project를 설정한다.

```bash
gcloud auth login
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"
```

GKE credentials를 가져온다.

```bash
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"
```

## 기본 점검 명령어

| 명령 | 기대 결과 |
|---|---|
| `kubectl cluster-info` | Kubernetes control plane endpoint 확인 |
| `kubectl get nodes` | GKE node pool의 node가 `Ready` 상태 |
| `kubectl get namespaces` | `default`, `kube-system` 등 기본 namespace 확인 |
| `kubectl get pods -A` | system pod가 `Running` 또는 정상 진행 상태 |
| `kubectl get svc` | default namespace service 상태 확인 |

## 확인할 Terraform Output

| output | 사용 위치 |
|---|---|
| `gke_cluster_name` | `CLUSTER_NAME` 값 확인 |
| `gke_cluster_location` | `REGION` 또는 cluster location 확인 |
| `gke_node_service_account_email` | GKE node identity와 Artifact Registry image pull IAM 확인 |
| `network_name` | GCP Console 네트워크 확인 |
| `subnet_name` | GCP Console subnet 확인 |

## 접속 실패 시 확인 포인트

| 증상 | 확인 항목 |
|---|---|
| credentials 획득 실패 | project ID, region, cluster name, IAM 권한 |
| `gke-gcloud-auth-plugin` 누락 경고 | `gke-gcloud-auth-plugin --version`, Google Cloud CLI component 또는 apt package 설치 여부 |
| `kubectl: command not found` | `kubectl version --client`, 로컬 `kubectl` 설치 여부 |
| `kubectl` 인증 실패 | kubeconfig context, gcloud active account |
| node가 보이지 않음 | Terraform apply 완료 여부, node pool 생성 상태 |
| system pod 비정상 | GKE Console cluster status, node resource 상태 |

## 검증 기록 기준

- 이 문서에는 절차와 기대 결과만 유지한다.
- 실제 실행 날짜, 명령, 결과 요약, 캡처 위치는 `docs/07-validation.md`에 기록한다.
- 의미 있는 실패가 발생하면 `docs/08-troubleshooting.md`에 원인과 해결을 남긴다.
