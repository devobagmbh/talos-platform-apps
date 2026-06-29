# automation/actions-runner-controller

Self-hosted GitHub Actions runners via **ARC** (`gha-runner-scale-set-controller`). The
controller reconciles the `actions.github.com` CRs into ephemeral runner pods. Self-hosted
runners do **not** count against the GitHub Actions free tier (issue #397).

- **Capability:** `ci-runner` (proposed, #412) — the swappable runner infrastructure.
- **Strict-B pair (ADR-0028):** CRDs in [`automation/actions-runner-controller-crds`](../actions-runner-controller-crds) (sync-wave −1); this controller workload at sync-wave 0.
- **Chart:** `gha-runner-scale-set-controller` 0.14.2, vendored (OCI-only chart — `render:one` does not pull OCI). Namespace `arc-system`, PSA `restricted` (hardened: runAsNonRoot, seccompProfile RuntimeDefault, allowPrivilegeEscalation false, capabilities drop ALL, readOnlyRootFilesystem).

## Pull-based — no inbound route

ARC is **pull-based**: the controller's listener opens an **outbound** long-poll HTTPS
connection to GitHub's Actions service and pulls jobs. **No ingress / firewall hole / route
into the cluster is needed** — egress to GitHub only.

## Consumer overlay (NOT in the catalog)

The catalog ships only the cluster-scoped controller + RBAC + namespace. Per cluster, the
consumer adds an `AutoscalingRunnerSet` (the `gha-runner-scale-set` chart / CR) with:

- **`githubConfigUrl`** — org (`https://github.com/<org>`) or repo URL. Org scope + a runner
  group governs which repos may use the runners.
- **GitHub App registration secret** (no PAT — ADR-0025): keys `github_app_id`,
  `github_app_installation_id`, `github_app_private_key`, via SOPS → ESO/Vault. App creation: #437.
- **`minRunners` / `maxRunners`** (catalog stays conservative; e.g. 0–3) + runner node-pool selection.
- **Runner-pod isolation** — default-deny against internal infra + an egress allowlist for what a
  build needs. Lives in the consumer's runner namespace (the catalog cannot know it): see
  [`examples/runner-isolation.example.yaml`](examples/runner-isolation.example.yaml).

## Vendoring (regenerate on a chart bump)

```bash
helm template arc \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version 0.14.2 --namespace arc-system --skip-crds \
  --set resources.requests.cpu=50m --set resources.requests.memory=64Mi --set resources.limits.memory=256Mi \
  --set securityContext.allowPrivilegeEscalation=false --set securityContext.readOnlyRootFilesystem=true \
  --set securityContext.runAsNonRoot=true --set 'securityContext.capabilities.drop={ALL}' \
  --set securityContext.seccompProfile.type=RuntimeDefault \
  | awk '/^(apiVersion:|---)/{f=1} f'   # → manifests/10-controller.yaml (below the header)
```

Bump the chart version here **and** in `actions-runner-controller-crds` (keep the strict-B pair in lockstep) + `compatibility.yaml`.
