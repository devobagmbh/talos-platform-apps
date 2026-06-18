# Sub-layer `registry`

Harbor as a container / OCI registry with pull-through cache and OCI artifact support.

OCI distribution per component (ADR-0009).

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`harbor`](components/harbor/) | 0 | Helm `harbor/harbor` (incl. Trivy subchart) | `oci://.../registry/harbor:vX.Y.Z` |

Cross-sub-layer dependencies: needs `databases/cnpg` (Postgres) and `storage-objects/garage` (S3 bucket).

## Consumed by

- A consumer that needs a pull-through cache — as a pull-through cache in front of GHCR / Docker Hub
- A consumer that needs a workload registry — as its own workload registry

Both consumers run Harbor independently.

## Backlog issues

- [#14 — Sub-layer `registry/`: Harbor](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+registry)
- [#27 — configure pull-through-cache Harbor (OIDC + pre-warm)](https://github.com/devobagmbh/talos-platform-apps/issues/27)
- [#33 — workload-registry Harbor with CNPG Postgres](https://github.com/devobagmbh/talos-platform-apps/issues/33)

## Related ADRs

- ADR-0012 — Platform-Registry-Proxy
- ADR-0013 — In-cluster registry
- ADR-0009 — Platform-Layer-Model
