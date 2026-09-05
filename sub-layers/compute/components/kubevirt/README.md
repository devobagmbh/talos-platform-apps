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
`kubevirt-operator.yaml` at tag **v1.7.4**
(`https://github.com/kubevirt/kubevirt/releases/download/v1.7.4/kubevirt-operator.yaml`)
and the `KubeVirt` CR from `kubevirt-cr.yaml` at the same release
(`https://github.com/kubevirt/kubevirt/releases/download/v1.7.4/kubevirt-cr.yaml`).
KubeVirt publishes no anonymously-pullable Helm chart (the upstream install method is
`kubectl apply -f kubevirt-operator.yaml`), so this component is delivered as raw
manifests (`kind: manifests`) — the **non-CRD** objects extracted from the release
manifest via `yq 'select(.kind != "CustomResourceDefinition" and .kind != "Namespace")'`
(mikefarah/yq v4 — the python-yq on the devbox PATH emits JSON for this expression and
does not reproduce the committed bytes; the `Namespace` is authored in
`00-namespace.yaml`, see below). Nothing is hand-edited: no `replicas` pin, no
consumer-specific values, no invented pod labels.

## What ships

`manifests/00-namespace.yaml` — the `kubevirt` Namespace;
`manifests/10-operator.yaml` — the virt-operator workload; and
`manifests/20-kubevirt-cr.yaml` — the `KubeVirt` operator-config CR:

- **Deployment `virt-operator`** (ns `kubevirt`, image
  `quay.io/kubevirt/virt-operator:v1.7.4`) — the operator. On reconcile of the
  `KubeVirt` CR it deploys the virtualization control plane (`virt-api`,
  `virt-controller`) and the per-node `virt-handler` DaemonSet; those component
  images are derived from the `KUBEVIRT_VERSION` env value (`v1.7.4`) and injected at
  reconcile time — they are not listed in this manifest.
- **PriorityClass `kubevirt-cluster-critical`** — for core KubeVirt components.
- **ServiceAccount, Role + RoleBinding** (ns `kubevirt`) and the **ClusterRole +
  ClusterRoleBinding `kubevirt-operator`** — the operator RBAC; plus the aggregated
  **ClusterRole `kubevirt.io:operator`** (aggregates KubeVirt verbs into the cluster
  `admin`/`edit`/`view` roles).
- **`KubeVirt` CR `kubevirt`** (ns `kubevirt`) — the operator-config singleton, see
  below.

**Zero CustomResourceDefinition objects** — the CRD schema ships in
`compute/kubevirt-crds`, not here (strict-B workload half).

> **Operator RBAC provenance.** The operator `ClusterRole`s carry broad grants —
> including wildcard `resources`/`verbs` on the `kubevirt.io` / `cdi.kubevirt.io`
> API groups — taken **verbatim** from the upstream `kubevirt-operator.yaml` v1.7.4.
> They are part of `virt-operator`'s documented threat model (it reconciles the full
> KubeVirt control plane) and are **not** narrowed here: hand-narrowing upstream
> operator RBAC silently breaks reconciliation on the next version bump. Accepted as
> upstream-verbatim; re-derived on every version re-extraction.

## The `KubeVirt` CR — a catalog default (consumer-overridable)

This workload ships the `KubeVirt` CR as a **catalog default**, taken verbatim from
the base migration source. Its security/posture **spec values** are the
upstream defaults verbatim; the `app.kubernetes.io/*` labels (incl. `managed-by:
argocd`) are standard labels the base source carries on the minimal upstream CR. It is **not** consumer-owned-only: the platform
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
- `workloadUpdateStrategy.workloadUpdateMethods: [Evict]` — on operator upgrade, shut
  the VMI's pod down rather than leave the VM on a stale `virt-launcher`. `Evict` is
  **not** live migration ("Evict: Which results in the VMI's pod being shutdown" —
  [updating_and_deletion](https://kubevirt.io/user-guide/cluster_admin/updating_and_deletion/)):
  a VM under `runStrategy: always` returns in a fresh pod, i.e. the guest restarts.

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

The upstream `kubevirt-operator.yaml` ships a `kubevirt` Namespace carrying only
`pod-security.kubernetes.io/enforce: privileged`; the extraction drops it and the
`Namespace` is authored in `00-namespace.yaml` with the full audit/warn label triad at
the same enforce level (ADR-0032 namespace ownership). This component
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
- **Every version hop restarts running VMs.** With the catalog default
  `workloadUpdateMethods: [Evict]`, `virt-operator` shuts each VMI's pod down on
  upgrade, so a walk across N minors restarts every VM N times. A consumer running
  production VMs SHOULD override to `[LiveMigrateIfPossible]` in their overlay before
  starting a multi-hop walk — that needs at least two schedulable nodes and
  migration-capable hardware. Dev/test consumers may keep the default.
- **The v1.6 hop drops two `instancetype.kubevirt.io` API versions.** `v1alpha1` and
  `v1alpha2` are no longer served or supported upstream (KubeVirt PR #14048). Those
  CRDs are operator-installed at runtime (see above), so nothing in this artifact
  changes — but a consumer whose `VirtualMachine`s reference an instancetype or
  preference through `v1alpha{1,2}` MUST migrate those objects to `v1beta1` **before**
  applying this tag, or the VMs stop resolving their instancetype.
- **Two v1.6 monitoring contracts changed, and both fail silently.** A consumer MUST
  audit their observability layer **before** applying this tag; neither break produces
  an error, an Argo health signal, or a Kubernetes event.
  - `kubevirt_vmi_vcpu_seconds_total` switched unit from microseconds to nanoseconds
    (PR #13898). Every dashboard panel and alert expression doing arithmetic on it is
    off by 1000x — update the expressions.
  - The four `VirtHandlerRESTErrorsHigh`, `VirtOperatorRESTErrorsHigh`,
    `VirtAPIRESTErrorsHigh` and `VirtControllerRESTErrorsHigh` alerts were removed
    (PR #13911). Any alerting rule or runbook naming them goes dead — these are
    control-plane health canaries, so losing them undetected means missed incidents.
    Remove or replace the rules and fix the runbooks.

  This artifact ships no `PrometheusRule`, so both live entirely in the consumer's
  observability layer.
- **KubeVirt no longer creates PodDisruptionBudgets** (PR #13764). A consumer whose
  node-drain tooling or policy asserted the presence of a KubeVirt-managed PDB must
  stop relying on it. Under the catalog default `workloadUpdateMethods: [Evict]` this
  changes nothing — eviction is already the intended behaviour. A consumer who
  overrode to `[LiveMigrateIfPossible]` loses the PDB as a backstop: a failed migration
  now falls through to eviction with no mandatory delay window, where the PDB
  previously held it off.
- **`developerConfiguration.memoryOvercommit` is now bounded below at 10** in the CRD
  schema (`-crds` half), and the `-crds` half syncs FIRST (wave -1), so the new bound
  is active before the operator upgrades. A value of 1-9 was accepted before this hop
  and is rejected by the API server after it, which leaves the live CR unwritable and
  the operator unable to reconcile it. Check before syncing:

  ```console
  kubectl get kubevirt kubevirt -n kubevirt \
    -o jsonpath='{.spec.configuration.developerConfiguration.memoryOvercommit}'
  ```

  An empty result or a value ≥ 10 needs nothing. A value of 1-9 MUST be corrected to
  ≥ 10 (in the consumer overlay, then synced) before the `-crds` tag is applied. The
  catalog default does not set the field, so only an overlay can put a cluster in this
  state.
- **The v1.7 hop pins `virt-operator` to control-plane nodes** (PR #15157). The
  Deployment gains a `requiredDuringSchedulingIgnoredDuringExecution` node affinity on
  `node-role.kubernetes.io/control-plane` OR `node-role.kubernetes.io/master`, plus
  `NoSchedule` tolerations for both. On a cluster whose control-plane nodes carry
  neither label the Pod stays `Pending`, and because `virt-operator` is what reconciles
  the `KubeVirt` CR, the entire virtualization control plane stops upgrading. Check
  before applying:

  ```console
  kubectl get nodes -l node-role.kubernetes.io/control-plane
  ```

  An empty result means the nodes MUST be labelled before this tag is applied.
- **The v1.7 hop deletes the `instancetype.kubevirt.io/v1alpha{1,2}` CRDs** (PR
  #15400). The v1.6 hop stopped serving those versions; this hop removes the CRDs, and
  any stored objects still on them go with the CRDs. Migrating to `v1beta1` was
  advisable at v1.6 and is mandatory here.
- **`virt-operator` no longer honours the `*_SHASUM` env variables** (PR #15061). A
  consumer who pinned individual control-plane component images by digest through those
  variables MUST move the pin to the corresponding `*_IMAGE` variable, which takes a
  tag, a digest, or both.
- **The supported Kubernetes floor moves to 1.33** (PR #15718), and `virt-api` now
  scales its replica count with the number of `kubevirt.io/schedulable=true` nodes
  (PR #15690) — a consumer policy or dashboard asserting a fixed `virt-api` replica
  count goes stale.
- **`virt-operator` carries a new pod label**
  `np.kubevirt.io/allow-access-cluster-services: "true"`, upstream's selector for
  KubeVirt control-plane NetworkPolicies. Nothing breaks without it; a consumer running
  default-deny policies can select on it instead of on `kubevirt.io: virt-operator`.
- **cgroup v1 is in maintenance mode as of v1.6** (PR #14538) and upstream announces
  removal in a later release. Nodes still on cgroup v1 need to move to v2 before the
  chain reaches that release.

## Upgrade path — sequential, forward only

Upstream supports only **N-1 -> N** upgrades, each hop starting from the latest patch
of the current minor, and documents no downgrade path
([updating_and_deletion](https://kubevirt.io/user-guide/cluster_admin/updating_and_deletion/)).
The catalog therefore publishes **every** intermediate upstream minor as its own
release. Three obligations follow:

- **Apply the catalog tags in order.** Skipping a tag skips an upstream minor and puts
  the cluster on an unsupported upgrade path. Read the CHANGELOG to see which upstream
  version a catalog tag carries.
- **Rolling a minor back is unsupported.** `Prune=false` on the `-crds` `Application`
  protects against an accidental CR-cascade delete; it does **not** make a downgrade
  safe — re-pinning the `-crds` tag can re-apply the older CRD schema while the newer
  operator has already reconciled state against the newer one. Recovery from a failed
  hop is forward (finish the hop) or a restore from a pre-hop backup.
- **Take a cluster backup before every hop** (etcd snapshot or Velero), not only the
  first.

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
surface, not a drop-in. (The `-crds` half is api-surface-only with no capability — the schema
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
