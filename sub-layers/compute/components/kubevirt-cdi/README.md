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
at tag **v1.62.0**
(`https://github.com/kubevirt/containerized-data-importer/releases/download/v1.62.0/cdi-operator.yaml`,
vendored in `talos-platform-base` at
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
  `quay.io/kubevirt/cdi-operator:v1.62.0`) — the operator. On reconcile of the `CDI`
  CR it deploys the CDI control plane (`cdi-apiserver`, `cdi-controller`,
  `cdi-uploadproxy`); the per-component images (`cdi-controller`, `cdi-importer`,
  `cdi-cloner`, `cdi-apiserver`, `cdi-uploadserver`, `cdi-uploadproxy`) are pinned to
  `v1.62.0` via the operator container env (`CONTROLLER_IMAGE`, `IMPORTER_IMAGE`, …),
  not as separate objects here — the operator injects them at reconcile time.
- **ServiceAccount `cdi-operator`**, the **Role + RoleBinding `cdi-operator`** (ns
  `cdi`), and the **ClusterRole `cdi-operator-cluster` + ClusterRoleBinding
  `cdi-operator`** — the operator RBAC.
- **`CDI` CR `cdi`** (ns `cdi`) — the operator-config singleton, see below.

**Zero CustomResourceDefinition objects** — the CRD schema ships in
`compute/kubevirt-cdi-crds`, not here (strict-B workload half).

> **Operator RBAC provenance.** The `cdi-operator-cluster` `ClusterRole` carries broad
> grants — including wildcard `resources`/`verbs` on the `cdi.kubevirt.io` API group
> and `clusterrole`/`clusterrolebinding` write — taken **verbatim** from the upstream
> `cdi-operator.yaml` v1.62.0. They are part of `cdi-operator`'s documented threat
> model (it reconciles the full CDI control plane, including the RBAC for its
> operands) and are **not** narrowed here: hand-narrowing upstream operator RBAC
> silently breaks reconciliation on the next version bump. Accepted as
> upstream-verbatim; re-derived on every version re-extraction.

## The `CDI` CR — a catalog default (consumer-overridable)

This workload ships the `CDI` CR as a **catalog default**, taken verbatim from the
base migration source at v1.62.0. It is **not** consumer-owned-only: the platform
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
restricted-compatible at v1.62.0 — so the namespace admits them without softening to
`baseline` or `privileged`. CDI is **not** like KubeVirt here: it spawns no privileged
host-access DaemonSet, so `restricted` (not `privileged`) is correct.

The upstream `cdi-operator.yaml` ships **no** Namespace object, so the `Namespace`
(with the PSA labels) is authored in `00-namespace.yaml`. This component is the
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

**None** — `capabilities: []` is a deliberate design state (apis-only), not a
deferral. CDI is a supporting infrastructure component bundled into the `vm-runtime`
app (disk-image import for VMs), not a swappable interface of its own: no consumer
would swap CDI out independently of KubeVirt, so neither the CDI workload nor its CRD
carries a capability id. `catalog/capability-index.yaml` ties CDI to the `vm-runtime`
entry only as a bundled member (the `# kubevirt + kubevirt-cdi` comment), not as a
capability. Same shape as the `-crds` half and the precedents
`storage-block/piraeus-operator-crds` and `observability/prometheus-operator-crds`
(all apis-only with no capability).

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
