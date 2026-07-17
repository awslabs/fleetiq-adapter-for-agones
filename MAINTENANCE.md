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

- [x] Move both images to `python:3.12-slim` (was 3.8, EOL). Pinned to a minor;
      a comment notes digest pinning as the stronger option.
- [x] Bump dependencies to current releases. `requirements.txt` now lists only
      direct deps with version floors; pip resolves the rest. Verified via
      `pip install --dry-run`, which resolves to boto3 1.43.x, kubernetes 36.x,
      redis 5.x, click 8.x, requests 2.34.x, urllib3 2.x. Also dropped the
      redundant PyPI `ec2-metadata` pin (the module is vendored) and refactored
      the vendored module off the `cached-property` backport onto
      `functools.cached_property`.
- [ ] Upgrade Go: skipped — the Go pubsub is marked experimental (Phase 0) and
      is not the supported/deployed path.
- [~] Install script: switched kubectl to the version-stable upstream
      `dl.k8s.io` channel, moved cluster-autoscaler to `registry.k8s.io` (the
      `k8s.gcr.io` registry is retired), and bumped EKS/cluster-autoscaler to
      1.30. **Not runtime-verified** — the script provisions real AWS infra and
      must be tested end-to-end against an account before use.
- [~] Bitnami Redis subchart: left pinned with an in-file TODO. Upgrading needs
      `helm dependency update` against Bitnami's OCI catalog and re-vendoring
      the `.tgz`; tracked as a standalone, tested change (also enable auth/TLS).

> Legend: `[x]` done, `[~]` partially done / needs a live test, `[ ]` not done.

### Not verifiable in this environment

- Docker image builds (no Docker here) — CI's `docker-build` job covers them.
- Kubernetes API calls against the newer `kubernetes` client, and FleetIQ /
  Agones behavior — need a real cluster.
- The install script and Helm charts against a live AWS account / `helm`.

## Phase 3 — Security hardening

- [x] Scope IAM down from `gamelift:*` (install-script daemon policy now lists
      only Register/Update/Claim/DeregisterGameServer) and RBAC `verbs: ["*"]`
      (nodes/pods scoped to get/list/watch/patch, pods/eviction to create) in
      both the raw manifest and the Helm role template.
- [x] Enforce IMDSv2 (`HttpTokens: required`) in the launch template. Compatible
      because the metadata client already uses the v2 token flow.
- [x] Run containers as non-root (uid 1000 + `securityContext` with dropped
      capabilities and `RuntimeDefault` seccomp on both workloads); drop
      `--trusted-host` from the Dockerfiles; add a Trivy scan in CI
      (non-blocking until Phase 2 upgrades land).
- [x] Support Redis AUTH/TLS via optional `REDIS_PASSWORD` / `REDIS_TLS` env
      vars in both apps (backward compatible — unset means today's behavior).
      Recommended supported path: ElastiCache with in-transit encryption + an
      AUTH token. *(Enabling by default still requires wiring a password secret
      through the charts — tracked for a follow-up.)*
- [x] Replace the hardcoded personal Docker Hub images and specific ElastiCache
      endpoints in the raw manifests with clearly marked placeholders. *(Helm
      charts were already parameterized via values.)*

## Phase 4 — Operational hygiene

- [ ] Add resource requests/limits and liveness/readiness probes to the
      DaemonSet and Deployment.
- [ ] Add a unit test suite (the daemon's drain/cordon/taint logic is the
      highest-value target) and wire it into CI.
- [ ] Convert the `.docx` install guides to in-repo Markdown so docs are
      diffable, and reconcile them with the shell script.
- [ ] Decide project status: add a clear notice if it stays BETA/unmaintained,
      or drop the `[BETA]` labeling once Phases 1–3 land.
