# AGENTS.md

## Overview

This repository uses AI-assisted workflows to keep implementation structured, reviewable, and aligned with the project architecture.

This file defines:

- agent roles
- responsibility boundaries
- working workflow
- editing rules
- documentation update routing

Project principles, architecture scope, and completion criteria are defined in `CLAUDE.md`.

---

## Consistency Model

Use these sources together rather than treating stale documentation as automatically correct:

1. Implementation files show what currently exists.
2. `README.md` summarizes the current external-facing repository state.
3. `CLAUDE.md` defines project principles, scope, architecture direction, and completion criteria.
4. `docs/00` through `docs/10` provide topic-specific plans, procedures, validation records, troubleshooting notes, portfolio notes, and reproduction guidance.
5. `AGENTS.md` defines how AI agents should work in this repository.

If a doc conflicts with the implementation or `README.md`, do not blindly follow the stale doc. Identify the mismatch, update the relevant doc in the same phase, and keep `CLAUDE.md` aligned when the conflict affects project scope or architecture.

---

## Agent Roles

### Codex

Use Codex for:

- repository scaffolding
- directory and file creation
- repetitive boilerplate generation
- simple refactors
- low-risk updates across multiple files
- template creation
- mechanical formatting and consistency edits

Codex should not be the primary decision-maker for:

- architecture tradeoffs
- Terraform module boundary decisions
- GitOps workflow design
- Kubernetes design rationale
- portfolio-facing narrative quality

Codex is best used for speed, structure, and predictable edits after the design direction is clear.

### Claude Code

Use Claude Code for:

- Terraform design and implementation
- Terraform module boundaries and interfaces
- provider and version strategy
- Kubernetes manifest structure
- GitOps workflow design
- GitHub Actions workflow structure
- documentation quality
- troubleshooting analysis
- architecture reasoning
- validation planning
- repository consistency review

Claude Code is the primary design and implementation agent.

---

## Responsibility Split

### Codex Responsibilities

- create folders and base files
- generate placeholder templates
- expand predefined structures
- perform predictable edits
- apply small repetitive changes
- help with simple code generation after design is fixed
- update stale references when the correct target is already known

### Claude Code Responsibilities

- define structure before implementation
- design and implement Terraform modules
- refine CI/CD and GitOps flows
- improve documentation quality
- explain why a structure is correct
- keep architecture, code, and docs aligned
- review and improve Codex output

---

## Working Rules

1. Work in small, reviewable steps.
2. Do not make large unrelated changes in one pass.
3. Keep architecture, Terraform, Kubernetes, CI, GitOps, and docs consistent.
4. Prefer clear and explainable implementations.
5. Avoid unnecessary complexity.
6. Use placeholders and TODO markers where values are not finalized.
7. Record meaningful decisions in the relevant docs.
8. Do not silently introduce major new tools or patterns.
9. Do not mark planned work as completed before validation exists.

---

## Project Workflow

Follow this sequence unless there is a strong reason to change it:

1. Align repository guidance and project overview:
   - `CLAUDE.md`
   - `AGENTS.md`
   - `README.md`
   - `docs/00-project-overview.md`
   - `docs/02-implementation-plan.md`
2. Confirm repository structure and naming.
3. Finalize architecture:
   - `docs/01-architecture.md`
4. Define Terraform plan:
   - `docs/03-terraform-plan.md`
5. Implement Terraform modules.
6. Validate GCP infrastructure creation.
7. Connect to GKE and validate cluster bootstrap:
   - `docs/04-gke-bootstrap.md`
8. Deploy the sample app:
   - `docs/05-app-deployment.md`
9. Implement GitHub Actions CI and Argo CD GitOps:
   - `docs/06-gitops-cicd.md`
10. Run validation and troubleshooting updates:
   - `docs/07-validation.md`
   - `docs/08-troubleshooting.md`
11. Maintain the from-scratch reproduction runbook:
   - `docs/10-reproduction-runbook.md`
12. Refine portfolio-facing notes:
   - `README.md`
   - `docs/09-portfolio-notes.md`

---

## File Ownership Guidance

### High-Priority Design Files

These should be primarily written or reviewed by Claude Code:

- `CLAUDE.md`
- `AGENTS.md`
- `README.md`
- `docs/00-project-overview.md`
- `docs/01-architecture.md`
- `docs/02-implementation-plan.md`
- `docs/03-terraform-plan.md`
- `docs/06-gitops-cicd.md`
- `docs/07-validation.md`
- `docs/08-troubleshooting.md`
- `docs/09-portfolio-notes.md`

### Infrastructure Files

These should be primarily designed by Claude Code:

- `terraform/main.tf`
- `terraform/variables.tf`
- `terraform/outputs.tf`
- `terraform/modules/network/*`
- `terraform/modules/gke/*`
- `terraform/modules/artifact_registry/*`

### Kubernetes Files

These should be designed by Claude Code, then mechanically updated if needed:

- `k8s/deployment.yaml`
- `k8s/service.yaml`
- `k8s/ingress.yaml`
- `gitops/argocd-app.yaml`

### Boilerplate-Friendly Files

These can be scaffolded or mechanically updated by Codex first:

- `docs/04-gke-bootstrap.md`
- `docs/05-app-deployment.md`
- `.github/workflows/ci.yml`
- `app/*` initial templates

---

## Area Guidance

Terraform work must follow `CLAUDE.md` and `docs/03-terraform-plan.md`. Claude Code should lead module design; Codex can apply mechanical updates once interfaces are defined.

Kubernetes work must follow `CLAUDE.md`, `docs/01-architecture.md`, and `docs/05-app-deployment.md`. Keep the first version limited to `Deployment`, `Service`, `Ingress`, and Argo CD `Application` unless a documented decision expands the scope.

CI/CD and GitOps work must follow `docs/06-gitops-cicd.md`. GitHub Actions owns CI image build/push. Argo CD owns CD synchronization from Git desired state.

Documentation work must stay honest about project status. Planned work belongs in `docs/02-implementation-plan.md` or TODO sections; completed work needs matching implementation or validation evidence.

---

## Documentation Update Routing

| Change Type | Update |
|---|---|
| project purpose, scope, deliverables | `docs/00-project-overview.md`, `README.md`, and possibly `CLAUDE.md` |
| architecture, traffic flow, resource responsibility | `docs/01-architecture.md`, `README.md`, and possibly `CLAUDE.md` |
| phase status, blockers, next tasks | `docs/02-implementation-plan.md` |
| Terraform module/resource/variable/output changes | `docs/03-terraform-plan.md` |
| GKE access or bootstrap procedure changes | `docs/04-gke-bootstrap.md` |
| app image or Kubernetes deployment flow changes | `docs/05-app-deployment.md` |
| GitHub Actions, Artifact Registry, or Argo CD flow changes | `docs/06-gitops-cicd.md` |
| executed checks and evidence | `docs/07-validation.md` |
| meaningful failures, fixes, and prevention notes | `docs/08-troubleshooting.md` |
| repeatable from-scratch execution, verification commands, cleanup procedure, or common failure points | `docs/10-reproduction-runbook.md` |
| portfolio talking points or future improvements | `docs/09-portfolio-notes.md`, `README.md` |

---

## Validation Guidance

Validation must happen incrementally. Do not treat code generation alone as completion.

Expected checkpoints include:

- `terraform init`
- `terraform validate`
- `terraform plan`
- `terraform apply`
- GCP Console resource verification
- `kubectl get nodes`
- `kubectl get pods -A`
- `kubectl get svc`
- Ingress or external access check
- GitHub Actions workflow result
- Artifact Registry image check
- Argo CD sync/application health

Record actual validation results in `docs/07-validation.md`. Record useful failure analysis in `docs/08-troubleshooting.md`. Keep repeatable execution and cleanup procedures in `docs/10-reproduction-runbook.md`.

---

## Editing Rules

1. Preserve existing structure unless there is a clear improvement.
2. Do not rename directories or docs casually.
3. Do not introduce large reorganizations mid-implementation.
4. Keep file names stable once referenced in docs.
5. Do not delete useful documentation history without reason.
6. If a change impacts docs, update docs in the same phase.
7. If a change impacts architecture assumptions, update `docs/01-architecture.md`.
8. If a change impacts public-facing status or structure, update `README.md`.
9. If a change impacts project scope or completion criteria, update `CLAUDE.md`.

---

## Commit And Change Style

When making changes:

- keep them focused
- group related edits together
- avoid mixing infrastructure, app, and docs changes without reason
- prefer step-by-step progress
- leave clear TODO markers rather than vague partial implementations

A good change should be easy to review and explain.

---

## Things To Avoid

- overengineering for appearance only
- adding advanced platform features too early
- mixing unrelated technologies without clear need
- hiding unfinished values instead of marking TODO
- making the project harder to explain
- writing docs that do not match implementation
- committing secrets or account-specific sensitive values
- allowing stale docs to override the actual repository state

---

## Completion Standard

A phase is complete only when:

- implementation exists
- validation is performed when applicable
- relevant docs are updated
- naming and architecture stay consistent
- placeholders or TODOs are clearly identified

The final repository should be technically coherent, modular, explainable, reproducible, and presentable as a cloud/platform portfolio project.
