# CLAUDE.md

## Project

`gcp-gke-gitops-pipeline`

## Purpose

This repository is a portfolio-oriented GCP platform project that integrates:

- GKE-based application hosting
- GitOps deployment with Argo CD
- CI with GitHub Actions
- Container storage with Artifact Registry
- Infrastructure as Code with modular Terraform
- clear documentation for architecture, implementation, validation, and troubleshooting

The goal is to produce a reusable and explainable cloud engineering project, not an overbuilt enterprise platform.

---

## Primary Outcomes

The repository should demonstrate:

1. GKE platform architecture on GCP.
2. Terraform-based infrastructure provisioning with readable module boundaries.
3. CI image build/push flow through GitHub Actions and Artifact Registry.
4. GitOps-based Kubernetes synchronization through Argo CD.
5. Portfolio-quality documentation with validation evidence and troubleshooting notes.

---

## Core Architecture

The intended integrated flow is:

```text
User
  -> External HTTP(S) Load Balancer
  -> GKE Ingress
  -> Kubernetes Service
  -> sample-app Pods

Developer
  -> GitHub Repository
  -> GitHub Actions
  -> Artifact Registry

GitHub Repository
  -> Argo CD
  -> GKE Cluster

Terraform
  -> VPC/Subnet
  -> GKE Cluster and Node Pool
  -> Artifact Registry
```

Target region:

- `asia-northeast3`

Target node locations:

- `asia-northeast3-a`
- `asia-northeast3-c`

The cluster strategy is regional GKE with explicit node locations in `asia-northeast3-a` and `asia-northeast3-c` for predictable multi-zone placement and cost control. Terraform wires this through the root `gke_node_locations` variable and the GKE module `node_locations` setting; actual GCP creation, node count, and node readiness have been validated.

GKE nodes use a dedicated node service account instead of relying on the default Compute Engine service account. Terraform defines the GKE default node role `roles/container.defaultNodeServiceAccount` at project scope and grants Artifact Registry repository-scoped `roles/artifactregistry.reader` so the cluster can pull the sample app image after deployment.

The sample app has been manually built, pushed to Artifact Registry, deployed to GKE, and verified for image pull. The Service and hostless GCE Ingress have been applied; Service NEG auto annotation, Ingress backend/events, External IP assignment, and HTTP 200 access are validated. GitHub Actions has also pushed a commit-tagged image to Artifact Registry; Argo CD sync validation is the next phase.

---

## Scope

### In Scope

- GCP VPC and subnet
- GKE cluster and node pool
- Artifact Registry Docker repository
- Kubernetes `Deployment`, `Service`, and `Ingress`
- Argo CD `Application` manifest
- GitHub Actions workflow for image build and push
- Terraform modularization with `network`, `gke`, and `artifact_registry`
- documentation for implementation plan, validation, troubleshooting, and portfolio notes

### Out of Scope for Initial Version

- advanced private cluster networking
- service mesh or Istio
- multi-cluster architecture
- blue-green or canary rollout
- complex secret backends
- production hardening beyond the portfolio scope

Keep the project realistic, reproducible, and easy to explain.

---

## Engineering Principles

1. Prefer clarity over unnecessary complexity.
2. Keep architecture, Terraform, Kubernetes manifests, CI, GitOps, and docs aligned.
3. Every major component must have a clear reason to exist.
4. Avoid hidden assumptions, magic values, and undocumented placeholders.
5. Use explicit TODO markers where values or decisions are not finalized.
6. Build incrementally and validate each phase before moving on.
7. Record meaningful design decisions and validation evidence in the appropriate docs.

---

## Repository Baseline

The repository should stay aligned with this structure:

```text
gcp-gke-gitops-pipeline/
├─ README.md
├─ CLAUDE.md
├─ AGENTS.md
├─ app/
├─ terraform/
│  └─ modules/
│     ├─ network/
│     ├─ gke/
│     └─ artifact_registry/
├─ k8s/
├─ gitops/
├─ .github/workflows/
└─ docs/
   ├─ 00-project-overview.md
   ├─ 01-architecture.md
   ├─ 02-implementation-plan.md
   ├─ 03-terraform-plan.md
   ├─ 04-gke-bootstrap.md
   ├─ 05-app-deployment.md
   ├─ 06-gitops-cicd.md
   ├─ 07-validation.md
   ├─ 08-troubleshooting.md
   └─ 09-portfolio-notes.md
```

Do not rename stable directories or documentation files casually once they are referenced by `README.md` and other docs.

---

## Documentation Roles

| File | Role |
|---|---|
| `README.md` | external-facing summary, repository map, quick start, current status |
| `docs/00-project-overview.md` | project purpose, scope, stack, and deliverables |
| `docs/01-architecture.md` | GCP/GKE/Terraform/CI/GitOps architecture and design rationale |
| `docs/02-implementation-plan.md` | phase plan, current state, next work, blockers |
| `docs/03-terraform-plan.md` | Terraform module boundaries, resources, variables, outputs, validation plan |
| `docs/04-gke-bootstrap.md` | GKE access, credentials, and baseline `kubectl` checks |
| `docs/05-app-deployment.md` | sample app image and Kubernetes deployment flow |
| `docs/06-gitops-cicd.md` | GitHub Actions, Artifact Registry, and Argo CD responsibility split |
| `docs/07-validation.md` | executed validation commands, expected results, actual results, evidence |
| `docs/08-troubleshooting.md` | issues, root causes, fixes, verification, prevention notes |
| `docs/09-portfolio-notes.md` | portfolio talking points, lessons learned, and future improvements |
| `AGENTS.md` | AI-assisted role split, working rules, and editing guidance |

Documentation must describe the current implementation honestly. Do not present planned or placeholder work as completed.

---

## Terraform Rules

1. Terraform must stay modular.
2. Use these base modules:
   - `network`
   - `gke`
   - `artifact_registry`
3. Root Terraform should connect modules and remain readable.
4. Keep `main.tf`, `variables.tf`, and `outputs.tf` responsibilities clear.
5. Use variables for project-specific values.
6. Never hardcode secrets, credentials, or account-sensitive values.
7. Keep module interfaces simple and explicit.
8. Prefer portfolio-readable structure over unnecessary abstraction.
9. Add comments only where they improve understanding.
10. Use TODO placeholders for values not finalized yet.

---

## Kubernetes Rules

1. Keep manifests simple and readable.
2. Baseline manifests are:
   - `k8s/deployment.yaml`
   - `k8s/service.yaml`
   - `k8s/ingress.yaml`
   - `gitops/argocd-app.yaml`
3. `Deployment` represents the sample workload.
4. `Service` exposes the app inside the cluster.
5. `Ingress` represents external HTTP routing through GKE.
6. Do not introduce extra Kubernetes resources in the first version without a clear reason.
7. Keep names consistent across `app/`, `k8s/`, Terraform outputs, `README.md`, and docs.

---

## CI/CD And GitOps Rules

1. GitHub Actions handles CI:
   - optional test
   - Docker image build
   - push to Artifact Registry
2. Argo CD handles CD:
   - watches Git desired state
   - syncs Kubernetes manifests to GKE
3. Do not blur CI and CD responsibilities.
4. Keep image tag and manifest update strategy explicit when it is finalized.
5. Keep `docs/06-gitops-cicd.md` aligned with `.github/workflows/ci.yml` and `gitops/argocd-app.yaml`.
6. Initial GitHub Actions authentication uses GitHub OIDC and Workload Identity Federation as a documented manual prerequisite; Terraform automation for that setup is a later improvement.
7. Initial image tag promotion is manual: update the Kubernetes manifest with the pushed Artifact Registry image URI, then let Argo CD sync Git desired state.

---

## App Rules

1. The sample app can be minimal.
2. The app exists to validate the platform flow, not to dominate the project.
3. Containerization should be straightforward and reproducible.
4. Avoid application complexity that makes the platform harder to explain.

---

## Documentation Rules

1. Documentation is part of the deliverable.
2. Update docs in the same phase as related implementation changes.
3. Update `README.md` when the public-facing project summary, status, structure, or quick start changes.
4. Update `docs/01-architecture.md` when architecture assumptions change.
5. Update `docs/02-implementation-plan.md` when phase status or next work changes.
6. Update `docs/07-validation.md` with actual validation results, not only intended commands.
7. Update `docs/08-troubleshooting.md` when a meaningful issue is found and resolved.

---

## Validation Expectations

At minimum, validation should include:

- `terraform init`
- `terraform validate`
- `terraform plan`
- `terraform apply`
- GCP Console verification for VPC, subnet, GKE, and Artifact Registry
- `kubectl get nodes`
- `kubectl get pods -A`
- `kubectl get svc`
- Ingress or external access verification
- GitHub Actions workflow result
- Artifact Registry image confirmation
- Argo CD sync/application health

Validation results belong in `docs/07-validation.md`. Failures with useful lessons belong in `docs/08-troubleshooting.md`.

---

## Security And Safety Rules

1. Never commit secrets, tokens, keys, or credential files.
2. Never commit real project-sensitive `tfvars`.
3. Use placeholders for sensitive or account-specific values.
4. Use `.gitignore` to protect generated files, state, provider caches, and local credentials.
5. Do not expose personal or account-specific information in docs.
6. Avoid reckless permissions or vague security assumptions.

---

## Implementation Order

Follow this order unless there is a strong reason to change it:

1. Align repository guidance and documentation structure:
   - `CLAUDE.md`
   - `AGENTS.md`
   - `README.md`
   - `docs/00-project-overview.md`
   - `docs/02-implementation-plan.md`
2. Finalize architecture and naming:
   - `docs/01-architecture.md`
3. Define Terraform plan:
   - `docs/03-terraform-plan.md`
4. Implement Terraform modules.
5. Provision and validate GCP infrastructure.
6. Bootstrap and verify GKE access:
   - `docs/04-gke-bootstrap.md`
7. Deploy and verify the sample application:
   - `docs/05-app-deployment.md`
8. Configure GitHub Actions CI and Argo CD GitOps:
   - `docs/06-gitops-cicd.md`
9. Validate the end-to-end flow:
   - `docs/07-validation.md`
   - `docs/08-troubleshooting.md`
10. Refine portfolio-facing narrative:
   - `README.md`
   - `docs/09-portfolio-notes.md`

---

## Definition Of Done

This project is complete when:

- Terraform modules provision the intended GCP resources.
- GKE cluster access is validated.
- The sample app is deployed successfully.
- Ingress or external access is verified.
- GitHub Actions builds and pushes an image.
- Artifact Registry stores the built image.
- Argo CD syncs the workload to GKE.
- Docs explain the architecture, workflow, and decisions clearly.
- Validation evidence is recorded in `docs/07-validation.md`.
- Troubleshooting evidence is recorded in `docs/08-troubleshooting.md` when relevant.
- `README.md`, `CLAUDE.md`, `AGENTS.md`, and `docs/00` through `docs/09` do not contradict the implementation.

---

## Non-Goals

- Do not turn this into a large enterprise platform project.
- Do not add advanced features only for appearance.
- Do not sacrifice clarity for complexity.
- Do not drift away from the integrated architecture without documenting why.

---

## Working Style

- make focused, incremental changes
- explain important design choices
- keep code and docs synchronized
- prefer maintainable structure over fast but messy output
- optimize for explainability, reproducibility, and portfolio quality
