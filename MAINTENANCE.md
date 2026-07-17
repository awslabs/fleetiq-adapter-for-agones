# Maintenance Plan

This document tracks the maintenance and modernization work for the
`fleetiq-adapter-for-agones` project. It is organized into phases ordered by
risk and dependency. Phases 0–2 make the project safe to run again on current
infrastructure; Phases 3–4 are hardening and hygiene.

## Context

- The repo has been effectively dormant since August 2023; recent history is
  only Dependabot bumps.
- There are unmerged Dependabot branches on the remote, including a
  `urllib3-1.26.18` security bump.
- Components:
  - `gamelift-daemon/` (Python) — DaemonSet that registers/claims instances
    with GameLift FleetIQ and cordons/taints/drains nodes on `DRAINING`.
  - `pubsub/app/` (Python) — publishes per-instance FleetIQ status to Redis.
    The "current" implementation.
  - `pubsub/src/` (Go) — a second, "in development" pubsub implementation.
  - `pubsub/helm-chart/` + `gamelift-daemon/helm-chart/` — Helm charts.
  - `Agones_EKS_FleetIQ_Integration_Package[BETA]/` — shell script + `.docx`
    install guides.

## Phase 0 — Triage & guardrails

- [ ] Merge or close outstanding Dependabot PRs, starting with the `urllib3`
      security bump. *(Requires action on GitHub; not done in-repo.)*
- [x] Add CI (GitHub Actions) that builds both Docker images and runs a linter
      (`.github/workflows/ci.yml`). Lint fails only on real errors (syntax /
      undefined names); style issues are reported but non-blocking for now.
- [x] Choose a single pubsub implementation: the Python app in `pubsub/app` is
      the supported path; the Go version in `pubsub/src` is marked experimental
      and is not built/deployed.

## Phase 1 — Fix what's already broken *(in progress on `maintenance/phase-1-fixes`)*

- [x] Migrate the pod Eviction call from `policy/v1beta1` to `policy/v1`
      (the beta API was removed in Kubernetes 1.22, so draining is broken on
      current clusters).
- [x] Fix the `spot_instance_action` bug in `ec2_metadata.py` (it compared a
      `Response` object to an int and had no return on the success path).
- [x] Remove the `asyncio` backport pin from `requirements.txt` (the PyPI
      `asyncio` package must not be installed on modern Python; it shadows the
      stdlib module).
- [x] Replace `except Exception: pass` in `main()` with real error handling and
      swap `print(...)` for the `logging` module.

## Phase 2 — Runtime & dependency upgrades

- [ ] Move both images to a supported Python (3.12/3.13) slim base, pinned by
      digest.
- [ ] Bump `boto3`/`botocore`, `kubernetes` client, and `redis` to current
      releases; retest FleetIQ and Agones API calls.
- [ ] Upgrade Go to a supported version if Go is the chosen pubsub.
- [ ] Update the install script and charts to a supported EKS version,
      `registry.k8s.io` (the `k8s.gcr.io` registry is retired), and current
      cluster-autoscaler / Bitnami Redis chart versions.

## Phase 3 — Security hardening

- [ ] Scope IAM down from `gamelift:*` and RBAC `verbs: ["*"]` to the specific
      actions/resources actually used.
- [ ] Enforce IMDSv2 (`HttpTokens: required`) in the launch template.
- [ ] Run containers as non-root; drop `--trusted-host`; add image scanning
      (e.g. Trivy) in CI.
- [ ] Enable Redis auth/TLS, or document ElastiCache-with-auth as the supported
      path.
- [ ] Parameterize all hardcoded images/endpoints/account IDs through Helm
      values (currently references a personal Docker Hub account and specific
      ECR/ElastiCache endpoints).

## Phase 4 — Operational hygiene

- [ ] Add resource requests/limits and liveness/readiness probes to the
      DaemonSet and Deployment.
- [ ] Add a unit test suite (the daemon's drain/cordon/taint logic is the
      highest-value target) and wire it into CI.
- [ ] Convert the `.docx` install guides to in-repo Markdown so docs are
      diffable, and reconcile them with the shell script.
- [ ] Decide project status: add a clear notice if it stays BETA/unmaintained,
      or drop the `[BETA]` labeling once Phases 1–3 land.
