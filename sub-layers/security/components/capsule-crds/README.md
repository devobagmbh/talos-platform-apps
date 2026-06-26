# Component `security/capsule-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for
[Capsule](https://projectcapsule.dev/). It ships **only** the 11
`capsule.clastix.io` CustomResourceDefinitions rendered from the Capsule Helm
chart v0.13.7 — the operator workload is a **separate** component,
[`security/capsule`](../capsule/README.md). The two together form the strict-B
pair: CRDs first (this artifact, sync-wave -1), workload after (sync-wave 0).

The CRDs are rendered from the upstream Capsule Helm chart
(`https://projectcapsule.github.io/charts`, chart `capsule`, version `0.13.7`)
with `crds.inline=true` and `crds.exclusive=true`. The `inline` flag moves the
CRDs into the template output (so `helm template` without `--include-crds`
includes them), and `exclusive` suppresses all non-CRD chart primitives —
producing exactly 11 `kind: CustomResourceDefinition` objects and 0 objects of
any other kind.

## What ships

Exactly 11 resources, all in group `capsule.clastix.io`, served version `v1beta2`
(with `tenants.capsule.clastix.io` additionally serving `v1beta1` for migration):

| CRD | Kind | Scope |
|---|---|---|
| `capsuleconfigurations.capsule.clastix.io` | CapsuleConfiguration | Cluster |
| `customquotas.capsule.clastix.io` | CustomQuota | Namespaced |
| `globalcustomquotas.capsule.clastix.io` | GlobalCustomQuota | Cluster |
| `globaltenantresources.capsule.clastix.io` | GlobalTenantResource | Cluster |
| `quantityledgers.capsule.clastix.io` | QuantityLedger | Namespaced |
| `resourcepoolclaims.capsule.clastix.io` | ResourcePoolClaim | Namespaced |
| `resourcepools.capsule.clastix.io` | ResourcePool | Cluster |
| `rulestatuses.capsule.clastix.io` | RuleStatus | Namespaced |
| `tenantowners.capsule.clastix.io` | TenantOwner | Cluster |
| `tenantresources.capsule.clastix.io` | TenantResource | Namespaced |
| `tenants.capsule.clastix.io` | Tenant | Cluster |

No pods, no Services, no RBAC, no Namespace, no Deployment — the artifact is
purely the 11 CRDs. All operator workload resources ship in the workload artifact
`security/capsule`, not here.

The `CapsuleConfiguration` CR (the operator-config singleton) and `Tenant` CRs
are **consumer-owned** — they live in the consumer-cluster repo overlay, not in
this catalog component. This artifact only establishes the CRD schemas so those
CRs have registered types.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the workload:

1. **`security/capsule-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRDs (and cascading any live `Tenant` CRs plus other Capsule-typed
     resources) when the source removes them.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit (several Capsule CRD schemas are large) and is the convention for the
     strict-B `-crds` apps.

2. The workload Application **`security/capsule`** at sync-wave 0, which then
   comes up against CRDs that already exist.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`security/capsule`.

## Upgrading the CRD schemas

When this artifact is bumped to a newer Capsule release whose CRD schemas changed,
the consumer's Argo sync applies the new schemas in-place (ServerSideApply). Because
the consumer app runs `Prune=false`, fields the upstream removes are **not**
auto-pruned from the cluster; removal needs manual intervention. Bump the chart
`version` in `helm/capsule.yaml` and update `crd_schema` in `compatibility.yaml`
to match.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The Capsule CRDs are
the API surface (schemas/types), not a swappable operational capability. The
multitenancy capability is provided by the workload artifact `security/capsule`
(the capsule-controller-manager that reconciles Tenant CRs), not by the CRD
schemas alone (precedent: `compute/kubevirt-crds` and
`observability/prometheus-operator-crds`, likewise api-surface-only).

## Sync-wave

`-1` — the CRDs land before the capsule workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/security/capsule-crds:vX.Y.Z
```

The git tag is `security/capsule-crds-vX.Y.Z`; `task push` strips the leading
`v`, so the OCI registry tag is the bare SemVer (the component name is the OCI
*path*, not the tag).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
