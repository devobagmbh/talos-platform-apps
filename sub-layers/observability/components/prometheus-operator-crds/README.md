# Component `observability/prometheus-operator-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the
[Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator).
It ships **only** the `monitoring.coreos.com` CustomResourceDefinitions — the
controller workload is a **separate** component, `observability/prometheus-operator`.
The two together form the strict-B pair: CRDs first (this artifact, sync-wave -1),
controller after (sync-wave 0).

Vendored verbatim from the upstream
[`prometheus-operator/prometheus-operator`](https://github.com/prometheus-operator/prometheus-operator)
repository, tag **v0.91.0**, directory `example/prometheus-operator-crd-full/` — the
full CRD set (with field descriptions). These are exactly the 10
`monitoring.coreos.com` CRDs and nothing else — no controller, no Service, no RBAC,
no Namespace (CRDs are cluster-scoped). Delivered as raw vendored manifests
(`kind: manifests`, no Helm reference); re-vendor from the matching upstream tag on
every version bump.

## What ships

The 10 `monitoring.coreos.com` CustomResourceDefinitions:

- `alertmanagerconfigs.monitoring.coreos.com`
- `alertmanagers.monitoring.coreos.com`
- `podmonitors.monitoring.coreos.com`
- `probes.monitoring.coreos.com`
- `prometheusagents.monitoring.coreos.com`
- `prometheuses.monitoring.coreos.com`
- `prometheusrules.monitoring.coreos.com`
- `scrapeconfigs.monitoring.coreos.com`
- `servicemonitors.monitoring.coreos.com`
- `thanosrulers.monitoring.coreos.com`

No pods, no Services, no RBAC, no Namespace — the artifact is purely
cluster-scoped CRDs.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the controller:

1. **`prometheus-operator-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRDs (and cascading their `monitoring.coreos.com` CRs) when the
     source removes them. The Helm-layer `helm.sh/resource-policy: keep` is **not**
     honored by Argo for its own prune decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` clears the 262 KB annotation limit — the Prometheus
     Operator CRDs exceed it, so a client-side `kubectl apply` (last-applied
     annotation) would fail.

2. The workload Application **`observability/prometheus-operator`** at sync-wave 0,
   which then comes up against CRDs that already exist.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`observability/prometheus-operator`.

## Upgrading CRD schemas

When this artifact is bumped to a new upstream tag that changes CRD schemas, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Two
hazards to check before syncing a new version:

- **Validation tightening** — if a newer CRD adds or tightens field validation,
  existing `monitoring.coreos.com` CRs that violate the new rules are **not**
  auto-migrated; the operator may enter a reconciliation error loop. Check the
  upstream prometheus-operator changelog for validation changes and audit existing
  CRs before syncing.
- **Field removal** — because the consumer app runs `Prune=false`, fields/CRDs
  the upstream removes are **not** auto-pruned from the cluster; removal needs
  manual intervention. Never assume a downgrade or field drop reconciles itself.

CRD upgrades are forward-compatible by convention (the operator supports the
served versions), but a major operator bump (`v0.x` API churn) warrants a
controller-drain check in the consumer repo's runbook.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The `monitoring.coreos.com`
CRD group is the Prometheus Operator's own provider-exclusive API surface, not a
swappable capability with alternative implementations (precedent:
`lifecycle/providers`, likewise api-surface-only).

## Sync-wave

`-1` — CRDs land before the controller workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/prometheus-operator-crds:vX.Y.Z
```

## Consumed by

- A full-stack consumer — yes (full LGTM-A + Prometheus Operator stack).
- A forwarder-only consumer — yes (operator subset: the Prometheus Operator + Alloy forwarder).

Wherever `observability/prometheus-operator` runs, this CRDs artifact is a hard
prerequisite (Argo sync-wave -1).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
