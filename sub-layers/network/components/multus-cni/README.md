# Component `network/multus-cni`

The **strict-B WORKLOAD artifact** (talos-platform-docs ADR-0028) for
[multus-cni](https://github.com/k8snetworkplumbingwg/multus-cni). It ships the
**thin Multus controller** — a per-node DaemonSet plus its RBAC — that implements
CNI delegation, so pods can attach to additional networks beyond the default CNI
via `NetworkAttachmentDefinition` CRs.

The `NetworkAttachmentDefinition` CustomResourceDefinition itself is a
**separate** component, `network/multus-cni-crds` (sync-wave -1). The two
together form the strict-B pair: CRD first, controller after. This workload
artifact carries **0** `CustomResourceDefinition` resources.

The manifests are migrated verbatim from the upstream multus-cni release
**v4.2.4** (thin deployment). Multus publishes no official Helm chart, so this
component is delivered as raw manifests (`kind: manifests`).

## What ships

| Resource | Purpose |
|---|---|
| `ServiceAccount/multus` (kube-system) | controller identity |
| `ClusterRole/multus` + `ClusterRoleBinding/multus` | read/write `k8s.cni.cncf.io/*` (NetworkAttachmentDefinition), `pods`/`pods/status`, `events` |
| `DaemonSet/kube-multus-ds` (kube-system) | the thin Multus controller, one pod per node |

All images are pinned exactly — no `:latest`:

- controller + multus-binary init: `ghcr.io/k8snetworkplumbingwg/multus-cni:v4.2.4`
- cni-plugins init: `busybox:1.37`

No pods land outside `kube-system`; no Service; no `NetworkAttachmentDefinition`
CR (those are consumer config authored against the `-crds` schema).

## Namespace

The DaemonSet + RBAC deploy into `kube-system`, the **substrate-managed**
(base-layer) namespace. Per the catalog namespace convention (foreign namespace),
this component ships **no** `Namespace` object — `kube-system` is owned by the
substrate and its Pod Security Admission posture is set there, not here.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app
**before** this controller:

1. **`network/multus-cni-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   `Prune=false` is the authoritative CR-cascade protection (it stops Argo from
   deleting the CRD and cascading the consumer's live
   `NetworkAttachmentDefinition` CRs).

2. **`network/multus-cni`** (this workload) Application at
   `argocd.argoproj.io/sync-wave: "0"`, which then comes up against a CRD that
   already exists.

## Capability

Provides the swappable operational capability **`secondary-network-attachment`**
(`catalog/capability-index.yaml`: active implementation `multus-cni`,
`swap_class: rewrite-required`). This is the controller that *implements* CNI
delegation — distinct from the `-crds` half, which is apis-only (the CRD schema is
the API surface, not the operational capability). `rewrite-required` reflects that
replacing Multus with another secondary-network provider is not a drop-in swap.

## Consumer-facing caveats

Two operational properties the consumer MUST account for — neither is governed by
an on-disk conftest policy in this repo:

1. **cni-plugins runtime download / provenance gap.** The `install-cni-plugins`
   init-container fetches the containernetworking/plugins bundle at pod startup:

   ```text
   https://github.com/containernetworking/plugins/releases/download/v1.9.1/cni-plugins-linux-<arch>-v1.9.1.tgz
   ```

   This download happens **outside the cosign-signed artifact boundary** — the
   binaries are NOT covered by the OCI artifact's signature/SBOM. The init step is
   idempotent (skips if `macvlan`/`tuning`/`static`/`bridge` already exist on the
   host). Air-gapped or supply-chain-strict consumers MUST provide one of:
   - a mirror serving that exact URL, OR
   - a pre-staged `/opt/cni/bin/` on every node (the host hostPath the DaemonSet
     writes to), OR
   - a custom init image bundling the binaries (replacing the `busybox:1.37`
     init-container).

2. **privileged / hostNetwork.** The DaemonSet runs
   `securityContext.privileged: true` on every container/init-container and
   `hostNetwork: true`. This is **structurally required** for a CNI plugin — it
   writes CNI binaries to the host `/opt/cni/bin` and CNI config to
   `/etc/cni/net.d`, and shares the host network namespace. No on-disk conftest
   policy in this repo governs this posture; the consumer cluster's Pod Security
   Admission level for `kube-system` (substrate-managed) must permit it.

## Sync-wave

`0` — the controller lands after the CRD half (`network/multus-cni-crds`, wave -1).

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/network/multus-cni:<tag>
```

The git tag is `network/multus-cni-vX.Y.Z`; `task push` strips the leading `v`,
so the OCI registry tag is the bare SemVer.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

## Upstream

- <https://github.com/k8snetworkplumbingwg/multus-cni> (Apache-2.0)
