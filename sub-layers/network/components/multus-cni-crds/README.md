# Component `network/multus-cni-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for
[multus-cni](https://github.com/k8snetworkplumbingwg/multus-cni). It ships
**only** the `NetworkAttachmentDefinition` CustomResourceDefinition
(`k8s.cni.cncf.io`) — the Multus controller workload is a **separate** component,
`network/multus-cni`. The two together form the strict-B pair: CRD first (this
artifact, sync-wave -1), controller after (sync-wave 0).

The CRD is sourced verbatim from the upstream multus-cni release **v4.2.4**
(`deployments/multus-daemonset.yml`, the `CustomResourceDefinition` document).
Multus publishes no dedicated CRDs-only chart and no official Helm chart, so this
component is delivered as a raw manifest (`kind: manifests`).

## What ships

Exactly one cluster-scoped resource:

- `network-attachment-definitions.k8s.cni.cncf.io`
  (group `k8s.cni.cncf.io`, version `v1`, kind `NetworkAttachmentDefinition`,
  short name `net-attach-def`, scope `Namespaced`).

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD.

The CRD's `spec.config` field is an **open string** (a JSON-formatted CNI
configuration) with no structural schema. This is intentional upstream design:
the CNI delegation config is free-form, so the CRD does not constrain it. A
consumer authoring `NetworkAttachmentDefinition` CRs (macvlan/ipvlan/etc.) does
so against this open schema — those CR examples are consumer config, not catalog
content.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the controller:

1. **`multus-cni-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRD (and cascading the consumer's live
     `NetworkAttachmentDefinition` CRs, which would break multi-NIC pods) when the
     source removes it. The Helm-layer `helm.sh/resource-policy: keep` is **not**
     honored by Argo for its own prune decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit and is the convention for the strict-B `-crds` apps.

2. The workload Application **`network/multus-cni`** at sync-wave 0, which then
   comes up against a CRD that already exists.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`network/multus-cni`.

## Upgrading the CRD schema

When this artifact is bumped to a newer multus-cni release whose CRD schema
changed, the consumer's Argo sync applies the new schema in-place
(ServerSideApply). Because the consumer app runs `Prune=false`, fields the
upstream removes are **not** auto-pruned from the cluster; removal needs manual
intervention. A version bump is a separate reviewed change.

## Capability

apis-only, **no capability** — `capabilities: []`. The
`NetworkAttachmentDefinition` CRD is the API surface (schema), not a swappable
operational capability. The swappable capability `secondary-network-attachment`
is provided by the workload artifact `network/multus-cni` (the controller that
implements the CNI delegation), not by the CRD schema alone (precedent:
`observability/prometheus-operator-crds`, likewise apis-only).

## Sync-wave

`-1` — the CRD lands before the controller workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/network/multus-cni-crds:vX.Y.Z
```

The git tag is `network/multus-cni-crds-vX.Y.Z`; `task push` strips the leading
`v`, so the OCI registry tag is the bare SemVer.

## Related ADRs

- ADR-0028 — CRD management (strict B)
- ADR-0024 — Workload/Config Freeze-Line
- ADR-0009 — Platform-Layer-Model
