# Component `compute/kubevirt`

The **strict-B WORKLOAD artifact** (talos-platform-docs ADR-0028) for
[KubeVirt](https://github.com/kubevirt/kubevirt) — the operator that adds VM
workloads to Kubernetes. It ships the **virt-operator workload**, the `kubevirt`
**Namespace**, and the **`KubeVirt` operator-config CR**, and carries **zero CRDs**;
the single `kubevirt.io` `CustomResourceDefinition` (`kubevirts.kubevirt.io`) is the
**separate** strict-B CRD half,
[`compute/kubevirt-crds`](../kubevirt-crds/README.md). The two together form the
strict-B pair: CRD first (sync-wave -1), workload after (sync-wave 0).

The workload is sourced **verbatim** from the upstream KubeVirt release
`kubevirt-operator.yaml` at tag **v1.5.0**
(`https://github.com/kubevirt/kubevirt/releases/download/v1.5.0/kubevirt-operator.yaml`)
and the `KubeVirt` CR from `kubevirt-cr.yaml` at the same release
(`https://github.com/kubevirt/kubevirt/releases/download/v1.5.0/kubevirt-cr.yaml`).
KubeVirt publishes no anonymously-pullable Helm chart (the upstream install method is
`kubectl apply -f kubevirt-operator.yaml`), so this component is delivered as raw
manifests (`kind: manifests`) — the **non-CRD** objects extracted from the release
manifest via `yq 'select(.kind != "CustomResourceDefinition")'`. Nothing is
hand-edited: no `replicas` pin, no consumer-specific values, no invented pod labels.

## What ships

`manifests/00-namespace.yaml` — the `kubevirt` Namespace;
`manifests/10-operator.yaml` — the virt-operator workload; and
`manifests/20-kubevirt-cr.yaml` — the `KubeVirt` operator-config CR:

- **Deployment `virt-operator`** (ns `kubevirt`, image
  `quay.io/kubevirt/virt-operator:v1.5.0`) — the operator. On reconcile of the
  `KubeVirt` CR it deploys the virtualization control plane (`virt-api`,
  `virt-controller`) and the per-node `virt-handler` DaemonSet; those component
  images are pinned to the v1.5.0 shasums baked into the virt-operator container env
  (not in this manifest — the operator injects them at reconcile time).
- **PriorityClass `kubevirt-cluster-critical`** — for core KubeVirt components.
- **ServiceAccount, Role + RoleBinding** (ns `kubevirt`) and the **ClusterRole +
  ClusterRoleBinding `kubevirt-operator`** — the operator RBAC; plus the aggregated
  **ClusterRole `kubevirt.io:operator`** (aggregates KubeVirt verbs into the cluster
  `admin`/`edit`/`view` roles).
- **`KubeVirt` CR `kubevirt`** (ns `kubevirt`) — the operator-config singleton, see
  below.

**Zero CustomResourceDefinition objects** — the CRD schema ships in
`compute/kubevirt-crds`, not here (strict-B workload half).

## The `KubeVirt` CR — a catalog default (consumer-overridable)

This workload ships the `KubeVirt` CR as a **catalog default**, verbatim from the
upstream v1.5.0 `kubevirt-cr.yaml`. It is **not** consumer-owned-only: the platform
provides a posture default, and a consumer **patches it via their own Argo overlay**
(Kustomize/values in the consumer-cluster repo) where they need to diverge. The
shipped spec preserves these security/posture values, which the catalog **does not
soften**:

- `configuration.developerConfiguration.useEmulation: false` — require hardware
  virtualization (KVM); never silently fall back to software emulation. A consumer
  running on hardware **without** vt-x/amd-v overrides this to `true` in their
  overlay.
- `configuration.network.permitBridgeInterfaceOnPodNetwork: false` — block bridge
  binding on the pod network (hardening default).
- `workloadUpdateStrategy.workloadUpdateMethods: [Evict]` — live-migrate/evict VMIs
  on operator upgrade rather than leaving them on stale `virt-launcher` pods.

It renders as exactly one `kind: KubeVirt` named `kubevirt`.

## Namespace & Pod Security Admission

`kubevirt` ships with `pod-security.kubernetes.io/enforce: privileged`. This level is
**required** because the operator dynamically creates the `virt-handler` DaemonSet at
runtime with `privileged: true` + `hostNetwork: true` — `virt-handler` manages VM
workloads on each node and needs host access; those pods are operator-created from
this `KubeVirt` CR and are NOT part of this manifest. The operator's **own** pod
(`virt-operator`) is `restricted`-compatible (`runAsNonRoot: true`,
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
`seccompProfile: RuntimeDefault`), but the namespace must admit the privileged
`virt-handler` the operator spawns, so the posture is set to the strictest level the
namespace's workloads provably need: `privileged`. Same shape as
`storage-block/piraeus-operator` (a hardened operator pod, a privileged namespace for
the operator-created node DaemonSets).

The upstream `kubevirt-operator.yaml` ships **no** Namespace object, so the
`Namespace` (with the PSA labels) is authored in `00-namespace.yaml`. This component
is the **sole catalog occupant** of `kubevirt` (dedicated namespace), so it ships the
`Namespace` object; a shipped manifest takes precedence over Argo
`managedNamespaceMetadata`, making the PSA posture authoritative. The `-crds` half
ships no Namespace.

## Consumer obligations

- **The `KubeVirt` CR is a catalog default** — patch it via a consumer Argo overlay
  rather than forking this component (see above). Editing the bundled CR here is a
  catalog change, not a consumer concern.
- **Hardware prerequisites (substrate/base layer):** running VMs at native speed
  needs CPU virtualization (vt-x / amd-v) and the `kvm` kernel module on the nodes —
  a Talos system-extension / machine-config concern in the substrate layer,
  independent of this catalog artifact. The `vm-runtime` capability entry in
  `catalog/capability-index.yaml` records these as Layer-C (base) hardware features.
  Without them, set `useEmulation: true` in the consumer overlay (slower, for
  dev/test only).
- **Runtime VM CRDs** (`virtualmachines`, `virtualmachineinstances`, …) are
  **operator-installed at runtime** by `virt-operator` once the `KubeVirt` CR
  reconciles (ADR-0028 "operator-installed CRDs — out of scope"); they are neither in
  this workload nor in the `-crds` half.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app
**before** this workload:

1. **`compute/kubevirt-crds`** at `argocd.argoproj.io/sync-wave: "-1"` with
   `sync-options: Prune=false,ServerSideApply=true` (CR-cascade protection — keeps
   Argo from deleting the CRD and cascading the live `KubeVirt` CR + the
   operator-installed VM CRs — plus the large-CRD annotation-limit workaround).
2. **`compute/kubevirt`** (this artifact) at sync-wave 0, which then comes up against
   a CRD that already exists.

## crd-bearing pairing

This workload carries **0 CRDs** — the strict-B gate's oracle asserts
`kind: CustomResourceDefinition` count **== 0** here and **> 0** in the
`crd-bearing: true` half (`compute/kubevirt-crds`).

## Capability

Provides `vm-runtime` at `swap_class: rewrite-required` — present in
`catalog/capability-index.yaml` with kubevirt as the active implementation. Replacing
the VM-workload runtime means rewriting every VM/VMI manifest against a different CR
surface, not a drop-in. (The `-crds` half is apis-only with no capability — the schema
is the API surface, the operational capability lives here in the operator that
reconciles the `KubeVirt` CR into the virtualization control plane.)

## Sync-wave

`0` — the operator workload lands after its CRD half (wave -1).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/compute/kubevirt:vX.Y.Z
```

The git tag is `compute/kubevirt-vX.Y.Z`; `task push` strips the leading `v`, so the
OCI registry tag is the bare SemVer (the component name is the OCI *path*, not the
tag).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0018 — Policy Stack (Conftest)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md)
