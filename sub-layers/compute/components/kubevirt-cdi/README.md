# Component `compute/kubevirt-cdi`

The **strict-B WORKLOAD artifact** (talos-platform-docs ADR-0028) for the KubeVirt
[Containerized Data Importer (CDI)](https://github.com/kubevirt/containerized-data-importer)
— the operator that imports, uploads, and clones disk images into PVCs for KubeVirt
VMs. It ships the **cdi-operator workload**, the `cdi` **Namespace**, and the **`CDI`
operator-config CR**, and carries **zero CRDs**; the single `cdi.kubevirt.io`
`CustomResourceDefinition` (`cdis.cdi.kubevirt.io`) is the **separate** strict-B CRD
half, [`compute/kubevirt-cdi-crds`](../kubevirt-cdi-crds/README.md). The two together
form the strict-B pair: CRD first (sync-wave -1), workload after (sync-wave 0).

The workload is sourced **verbatim** from the upstream CDI release `cdi-operator.yaml`
at tag **v1.66.0**
(`https://github.com/kubevirt/containerized-data-importer/releases/download/v1.66.0/cdi-operator.yaml`,
migrated from `talos-platform-base`, where it was vendored at
`kubernetes/base/infrastructure/kubevirt-cdi/cdi-operator.yaml`) and the `CDI` CR
from `cdi-cr.yaml` at the same release. CDI publishes no anonymously-pullable Helm
chart (the upstream install method is `kubectl apply -f cdi-operator.yaml`), so this
component is delivered as raw manifests (`kind: manifests`) — the **non-CRD** objects
extracted from the release manifest via
`yq 'select(.kind != "CustomResourceDefinition" and .kind != "Namespace")'`. Nothing
is hand-edited: no `replicas` pin, no consumer-specific values, no invented pod labels.

## What ships

`manifests/00-namespace.yaml` — the `cdi` Namespace;
`manifests/10-operator.yaml` — the cdi-operator workload; and
`manifests/20-cdi-cr.yaml` — the `CDI` operator-config CR:

- **Deployment `cdi-operator`** (ns `cdi`, image
  `quay.io/kubevirt/cdi-operator:v1.66.0`) — the operator. On reconcile of the `CDI`
  CR it deploys the CDI control plane (`cdi-apiserver`, `cdi-controller`,
  `cdi-uploadproxy`); the per-component images (`cdi-controller`, `cdi-importer`,
  `cdi-cloner`, `cdi-apiserver`, `cdi-uploadserver`, `cdi-uploadproxy`) are pinned to
  `v1.66.0` via the operator container env (`CONTROLLER_IMAGE`, `IMPORTER_IMAGE`, …),
  not as separate objects here — the operator injects them at reconcile time.
- **ServiceAccount `cdi-operator`**, the **Role + RoleBinding `cdi-operator`** (ns
  `cdi`), and the **ClusterRole `cdi-operator-cluster` + ClusterRoleBinding
  `cdi-operator`** — the operator RBAC.
- **`CDI` CR `cdi`** (ns `cdi`) — the operator-config singleton, see below.

**Zero CustomResourceDefinition objects** — the CRD schema ships in
`compute/kubevirt-cdi-crds`, not here (strict-B workload half).

> **Operator RBAC provenance.** The `cdi-operator-cluster` `ClusterRole` carries broad
> grants — including wildcard `resources`/`verbs` on the `cdi.kubevirt.io`,
> `upload.cdi.kubevirt.io` and `forklift.cdi.kubevirt.io` API groups, and
> `clusterrole`/`clusterrolebinding` write — taken **verbatim** from the upstream
> `cdi-operator.yaml` v1.66.0. They are part of `cdi-operator`'s documented threat
> model (it reconciles the full CDI control plane, including the RBAC for its
> operands) and are **not** narrowed here: hand-narrowing upstream operator RBAC
> silently breaks reconciliation on the next version bump. Accepted as
> upstream-verbatim; re-derived on every version re-extraction.
>
> `forklift.cdi.kubevirt.io` entered that wildcard rule at v1.63.1, widening it from
> `get`/`list`/`watch` on `ovirtvolumepopulators` + `openstackvolumepopulators` to all
> verbs on all resources in the group (upstream v1.63.0, "BugFix: Add missing RBAC for
> ovirt and openstack volume populator CRDs").

## The `CDI` CR — a catalog default (consumer-overridable)

This workload ships the `CDI` CR as a **catalog default**, taken verbatim from the
base migration source. It is **not** consumer-owned-only: the platform
provides a posture default, and a consumer **patches it via their own Argo overlay**
(Kustomize/values in the consumer-cluster repo) where they need to diverge. The one
field that is genuinely cluster-specific is preserved **empty** and MUST stay empty
in the catalog:

- `config.uploadProxyURLOverride: ""` — the externally-reachable URL of the
  `cdi-uploadproxy` (e.g. via an Ingress/Gateway the consumer owns). Hardcoding it in
  the catalog would bake one cluster's topology into the shared artifact; leaving it
  empty lets the operator derive the in-cluster default. A consumer exposing the
  upload proxy externally sets it in their overlay.

It renders as exactly one `kind: CDI` named `cdi`.

## Namespace & Pod Security Admission

`cdi` ships with `pod-security.kubernetes.io/enforce: restricted`. This is the
**strictest level the namespace's workloads provably satisfy**: the `cdi-operator`
Deployment is `restricted`-compliant (pod `runAsNonRoot: true`; every container
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `runAsNonRoot: true`,
`seccompProfile: RuntimeDefault`), and the control-plane pods the operator creates at
reconcile time (`cdi-apiserver`, `cdi-controller`, `cdi-uploadproxy`) are likewise
restricted-compatible at v1.66.0 — so the namespace admits them without softening to
`baseline` or `privileged`. CDI is **not** like KubeVirt here: it spawns no privileged
host-access DaemonSet, so `restricted` (not `privileged`) is correct.

The upstream `cdi-operator.yaml` ships a `cdi` Namespace carrying no PSA labels at
all; the extraction drops it and the `Namespace` is authored in `00-namespace.yaml`
with the full PSA label triad (ADR-0032 namespace ownership). This component is the
**sole catalog occupant** of `cdi` (dedicated namespace), so it ships the `Namespace`
object; a shipped manifest takes precedence over Argo `managedNamespaceMetadata`,
making the PSA posture authoritative. The `-crds` half ships no Namespace.

## Consumer obligations

- **The `CDI` CR is a catalog default** — patch it via a consumer Argo overlay rather
  than forking this component. Setting `config.uploadProxyURLOverride` (the only
  cluster-specific field) is a consumer overlay concern.
- **Runtime CDI CRDs** (`datavolumes.cdi.kubevirt.io`, `datasources.cdi.kubevirt.io`,
  `cdiconfigs.cdi.kubevirt.io`, …) are **operator-installed at runtime** by
  `cdi-operator` once the `CDI` CR reconciles (ADR-0028 "operator-installed CRDs — out
  of scope"); they are neither in this workload nor in the `-crds` half.
- **Metrics scrape target moved at v1.63.1** — the `cdi-operator` metrics container
  port moved `8080` -> `8443` (upstream v1.63.0: "Metrics port for
  cdi-prometheus-metrics service changed from 8080 to 8443"). The port NAME is
  unchanged (`metrics`), so a `ServiceMonitor`/`PodMonitor` selecting by port name
  needs no change; one pinned to the numeric port `8080` MUST be retargeted to `8443`
  or it silently stops scraping. This artifact ships no `Service` — the
  `cdi-prometheus-metrics` `Service` is operator-created at reconcile time, so there
  is no stale `targetPort` in the catalog artifact to update.
- **Default filesystem overhead rose at v1.63.1** — upstream raised
  `DefaultGlobalOverhead` from `0.055` to `0.06` (`pkg/common/common.go`). A consumer
  who does not pin `spec.config.filesystemOverhead.global` in their `CDI` CR overlay
  gets 6% reserved overhead instead of 5.5% on newly provisioned Filesystem-mode
  PVCs. Existing PVCs are unaffected; pin the field to keep the old value.
- **The `CriticalAddonsOnly` toleration was removed at v1.64.0** (upstream: "BugFix:
  Removal of CriticalAddonsOnly toleration from CDI pods"). The `cdi-operator`
  Deployment this artifact ships no longer tolerates that taint, so on a cluster where
  the only eligible nodes carry it the operator pod goes `Pending` after this hop. A
  consumer in that position re-adds the toleration through their Kustomize overlay —
  `spec.infra.tolerations` in the `CDI` CR does **not** cover it, that field governs
  only the control-plane pods the operator creates. **Order matters:** the overlay MUST
  be committed and synced BEFORE the tag is bumped. Applying the tag first leaves
  `cdi-operator` `Pending`, which stalls every DataVolume import, disk-image upload and
  boot-from-DataVolume until the overlay lands. Running VMs are unaffected — CDI
  downtime blocks disk-image operations, not the VMs themselves.
- **A new `health` container port 8444 carries the v1.64.0 probes.** The operator
  gained a `readinessProbe` (`/readyz`) and `livenessProbe` (`/healthz`) on 8444,
  alongside the unchanged `metrics` port 8443. A failing probe now restart-loops the
  operator where v1.63.1 had no probe at all, so a consumer running a default-deny
  ingress posture in `cdi` SHOULD confirm the new port is reachable from the node
  before applying this tag. Whether a `NetworkPolicy` applies to kubelet probe traffic
  at all is CNI-dependent (host-sourced traffic is admitted by default under some
  CNIs), so verify against the cluster's own CNI rather than assuming either way. The
  pod template also gained the upstream NetworkPolicy selector label
  `np.kubevirt.io/allow-access-cluster-services: "true"`; this artifact ships no
  `NetworkPolicy`, the label is only a selector handle.
- **Restores from a VolumeSnapshot source are no longer size-inflated** (v1.64.0
  bugfix). CDI's PVC mutating webhook previously inflated a direct restore from a
  snapshot source, which strict CSI drivers rejected. A consumer who compensated for
  that inflation by over-requesting the restore size SHOULD drop the compensation.

- **Four CDI metrics are deprecated at v1.65.0** (upstream PR #4038) in favour of
  recording-rule-conforming names: `kubevirt_cdi_clone_pods_high_restart`,
  `..._import_pods_high_restart` and `..._upload_pods_high_restart` become
  `cluster:<same>:count`, and `kubevirt_cdi_operator_up` becomes
  `cluster:kubevirt_cdi_operator_up:sum`. The old names still exist at this tag, so
  nothing breaks yet — but a consumer dashboard or alert naming them will go silent
  when upstream removes them. This artifact ships no `PrometheusRule`; the rename lives
  entirely in the consumer's observability layer.
- **Scratch-space PVCs now inherit the source PVC's StorageClass** rather than the
  cluster default (PR #4054). An import whose source class cannot provision the scratch
  volume — a snapshot-only or capacity-capped class, or one whose quota is already
  exhausted — now fails where it previously borrowed the default class. A consumer
  running imports against a non-default class SHOULD confirm that class can provision a
  second, temporary PVC before applying this tag.
- **CDI worker and upload pods changed shape at v1.65.0.** `enableServiceLinks` is now
  `false` on worker pods (PR #4067), so the per-Service environment variables
  Kubernetes used to inject are gone — a custom importer image reading them stops
  seeing them. The upload server moved to a **headless** Service (PR #4052), so a
  consumer NetworkPolicy or probe selecting it by ClusterIP needs to select pods
  instead. Neither affects a consumer using CDI through `DataVolume` objects only.

- **The `/metrics` endpoints now require authentication at v1.66.0** (upstream PR
  #4121). `cdi-deployment` and `cdi-operator` stop serving metrics to an anonymous
  client: a scraper MUST present a bearer token whose subject has `get` on the
  `/metrics` `nonResourceURL`. Upstream creates a `cdi-metrics-reader` ServiceAccount
  and ClusterRole for exactly this — the operator creates them at reconcile time, so
  they are not in this artifact. An existing `ServiceMonitor`/`PodMonitor` without
  `bearerTokenSecret` (or `authorization`) **goes silent without an error**: the target
  turns unhealthy, no Argo signal, no Kubernetes event. A consumer MUST update the
  scrape config in the same change as this tag. This is the same failure shape as the
  v1.63.1 port move above, one layer further in.
- **The `WebhookPvcRendering` feature gate is on by default at v1.66.0** (PR #4172),
  with the matching `config.webhookPvcRendering` field in the `CDI` CR schema
  (`-crds` half). PVC rendering now runs through the mutating webhook by default; a
  consumer who needs the old path must set the field explicitly to opt out.
- **Secure pprof endpoints are exposed on the controller and the operator** (PR #4161),
  which is why the operator ClusterRole gains `get` on the `/debug/pprof` and
  `/debug/pprof/*` `nonResourceURL`s. The endpoints are authenticated the same way
  `/metrics` is, so nothing is reachable anonymously; nothing is required of a
  consumer, but the grant is visible in the diff.

## Upgrade path — sequential by convention

The KubeVirt family documents only **N-1 -> N** upgrades, each hop starting from the
latest patch of the current minor
([updating_and_deletion](https://kubevirt.io/user-guide/cluster_admin/updating_and_deletion/)).
That page covers KubeVirt; **CDI's own upgrade constraint is unconfirmed** — neither
`doc/releases.md` nor the CDI user-guide page states a skip restriction. The catalog
therefore stages CDI conservatively, matching the family convention: **every**
intermediate upstream minor ships as its own release. The three obligations below hold
either way.

- **Apply the catalog tags in order.** Read the CHANGELOG to see which upstream version
  a catalog tag carries. Should CDI turn out to permit a skip, stepping through is still
  safe — the reverse is not.
- **Rolling a minor back is unsupported.** `Prune=false` on the `-crds` `Application`
  protects against an accidental CR-cascade delete; it does **not** make a downgrade
  safe — re-pinning the `-crds` tag can re-apply the older schema while the newer
  operator has already reconciled state against the newer one. Recovery from a failed
  hop is forward (finish the hop) or a restore from a pre-hop backup.
- **Take a cluster backup before every hop** (etcd snapshot or Velero), not only the
  first.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app
**before** this workload:

1. **`compute/kubevirt-cdi-crds`** at `argocd.argoproj.io/sync-wave: "-1"` with
   `sync-options: Prune=false,ServerSideApply=true` (CR-cascade protection — keeps
   Argo from deleting the CRD and cascading the live `CDI` CR + the operator-installed
   runtime CRs — plus the large-CRD annotation-limit workaround).
2. **`compute/kubevirt-cdi`** (this artifact) at sync-wave 0, which then comes up
   against a CRD that already exists.

## crd-bearing pairing

This workload carries **0 CRDs** — the strict-B gate's oracle asserts
`kind: CustomResourceDefinition` count **== 0** here and **> 0** in the
`crd-bearing: true` half (`compute/kubevirt-cdi-crds`).

## Capability

**None** — `capabilities: []` is a deliberate design state (api-surface-only), not a
deferral. CDI is a supporting infrastructure component bundled into the `vm-runtime`
app (disk-image import for VMs), not a swappable interface of its own: no consumer
would swap CDI out independently of KubeVirt, so neither the CDI workload nor its CRD
carries a capability id. `catalog/capability-index.yaml` ties CDI to the `vm-runtime`
entry only as a bundled member (the `# kubevirt + kubevirt-cdi` comment), not as a
capability. Same shape as the `-crds` half and the precedents
`storage-block/piraeus-operator-crds` and `observability/prometheus-operator-crds`
(all api-surface-only with no capability).

## Sync-wave

`0` — the operator workload lands after its CRD half (wave -1).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/compute/kubevirt-cdi:vX.Y.Z
```

The git tag is `compute/kubevirt-cdi-vX.Y.Z`; `task push` strips the leading `v`, so
the OCI registry tag is the bare SemVer (the component name is the OCI *path*, not
the tag).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0018 — Policy Stack (Conftest)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md)
