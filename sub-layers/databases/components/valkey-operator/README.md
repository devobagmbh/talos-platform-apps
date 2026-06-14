# Component `databases/valkey-operator`

**[hyperspike/valkey-operator](https://github.com/hyperspike/valkey-operator)** — ships the `valkeys.hyperspike.io/v1` (`Valkey`) CRD + the operator controller. Implements the **`redis-managed`** capability via **Valkey** (BSD-3, Linux Foundation fork of Redis 7.2; wire-protocol-compatible on port 6379).

> **Why Valkey instead of Redis?** Redis has been RSALv2/SSPL since 2024. Harbor itself is officially migrating from Redis to Valkey (goharbor/harbor#22935, target 2.16). The classic `spotahome/redis-operator` is de facto dead (last stable 12/2022). Valkey + hyperspike is license-clean and aligned with the Harbor roadmap. (apps #83, decision 2026-06-09.)
>
> **Component name:** `valkey-operator` (not the issue placeholder `redis-operator`) — the component is honestly what it deploys. The capability is still named `redis-managed` (protocol-oriented).

- **OCI path:** `oci://ghcr.io/devobagmbh/talos-platform-apps/databases/valkey-operator:vX.Y.Z`
- **sync-wave:** `0` — ships the `Valkey` CRD that consuming apps (Harbor cache) need
- **Source:** vendored release `install.yaml` v0.0.61 (raw manifests; no Helm)

## Operator vs. CR

This component ships **only the operator** (CRD + controller-manager + RBAC + namespace `valkey-operator-system`). Concrete `Valkey` CRs are **consumer-owned** (ADR-0024) and belong in the respective app sub-layer / the cluster repo — e.g. Harbor's cache (apps #84, wired in the consumer repo).

## Talos / Single-Node

- **No cert-manager needed** — the operator has no admission webhooks. cert-manager becomes a dependency only when a `Valkey` CR sets `spec.tls: true` with `certIssuer` (not the case for the cluster-internal Harbor cache).
- **Always cluster mode** (no true standalone): `nodes: 1` = one Valkey server holding all 16384 slots. With a single node there are practically no MOVED redirects → test with Harbor's Redis client.
- **Maturity:** pre-1.0 (v0.0.61). Known limitation: `replicas > 0` currently creates additional primaries instead of real replicas (upstream #186) → keep `replicas: 0` for single-node. Acceptable for a non-critical cache, **not** as state-critical primary storage.

## Example `Valkey` CR (reference — NOT part of this component)

```yaml
apiVersion: hyperspike.io/v1
kind: Valkey
metadata:
  name: harbor-cache
  namespace: harbor
spec:
  nodes: 1            # single node, all slots local
  replicas: 0         # see upstream #186
  tls: false          # no cert-manager
  prometheus: false
  volumePermissions: true
  storage:
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: synology-iscsi-storage
      resources: { requests: { storage: 8Gi } }
```

For a CR without `anonymousAuth`, the operator automatically creates a Secret of the same name (`data.password`, 16 characters); Harbor references it as `REDIS_PASSWORD` (wired in #84).

## Related ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0024 — Customization Contract](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md)
