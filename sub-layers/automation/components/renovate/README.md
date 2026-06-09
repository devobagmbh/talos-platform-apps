# Component `automation/renovate`

[Renovate](https://github.com/renovatebot/renovate) (self-hosted) — the
dependency-update bot that scans configured repositories for new upstream
versions and opens update PRs. It runs as a scheduled **CronJob** (no
long-running Deployment): each run starts the Renovate container, talks to the
configured Git host over the network, and exits.

Helm chart `renovate` from `https://docs.renovatebot.com/helm-charts`, pinned to
**46.184.3** (appVersion `43.216.3`). Ships a `ServiceAccount`, a global-config
`ConfigMap` (a do-nothing baseline until the consumer supplies a repository
list), and the scan `CronJob`. The image is the chart-pinned
`ghcr.io/renovatebot/renovate:43.216.3` — no `:latest`. Renovate needs no
in-cluster RBAC of its own (it talks to the Git host, not the apiserver), so no
ClusterRole/Role is created.

## Freeze-line (ADR-0024)

The **workload** (CronJob + ServiceAccount + global-config ConfigMap) is the
signed, pre-rendered artifact. **Consumer-owned** (Layer 3):

- **Secret (Shape c)** — the Git-host token, in an existing Secret
  `renovate-runtime-secret`, key `RENOVATE_TOKEN`. The rendered CronJob
  references that Secret by name via `envFrom.secretRef`; the catalog ships only
  the named reference, never a real credential (base Hard-Constraint). The
  consumer creates the Secret in the destination namespace (SOPS, applied
  out-of-band before sync).
- **Config (Shape b territory)** — the real Renovate config (target repository
  list, platform endpoint, onboarding behaviour, schedule windows) is tuned by
  the consumer in its overlay. The catalog default is a platform-agnostic,
  repo-agnostic baseline (`"repositories": []`) that scans nothing until the
  consumer supplies the list.

## Sync-wave

`0` — no inter-component dependency. This is the `automation` tier, distinct
from the bootstrap-0 / base-substrate ordering; Renovate has no other catalog
component it must wait for.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/automation/renovate:renovate-vX.Y.Z
```

## Consumed by

- **office-lab** — yes (watches the Devoba platform repos for upstream updates).
- **Seeder** — no.

## Capability

Provides `dependency-automation` (`catalog/capability-index.yaml`, domain
`automation`), `swap_class: rewrite-required`. The capability is `status:
proposed` in the index — the provider/consumer contract is still open and is
tracked as a follow-up; the swap_class declared here matches the index
implementation entry as it stands.

## Security defaults

The catalog default is deliberately conservative — the component scans nothing
and grants nothing until the consumer opts in:

- `autodiscover: false` + `"repositories": []` — no repository is scanned until
  the consumer supplies the list in its overlay.
- No in-cluster RBAC (no ClusterRole/Role) — Renovate talks only to the Git host.
- Resource requests/limits are set (memory ceiling) so a bursty, memory-hungry
  scan cannot OOM the node; consumers tune them per cluster.
- A Renovate scan executes package-manager / toolchain code. Consumers SHOULD
  additionally restrict egress (a `NetworkPolicy` allowing only the Git host +
  the package registries actually needed). Egress targets are consumer-specific,
  so this is a consumer-side follow-up, not part of the catalog default.

## Related ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
