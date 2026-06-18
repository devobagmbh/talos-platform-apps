# Component `storage-block/piraeus-operator`

The **strict-B WORKLOAD artifact** (talos-platform-docs ADR-0028) for the
[piraeus-operator](https://github.com/piraeusdatastore/piraeus-operator) — the
operator that brings up a replicated DRBD/LINSTOR block-storage cluster. It ships
the operator **workload only** and carries **zero CRDs**; the four `piraeus.io`
Linstor CustomResourceDefinitions are the **separate** strict-B CRD half,
[`storage-block/piraeus-operator-crds`](../piraeus-operator-crds/README.md). The
two together form the strict-B pair: CRDs first (sync-wave -1), workload after
(sync-wave 0).

The workload is sourced **verbatim** from the upstream piraeus-operator release
`manifest.yaml` at tag **v2.10.7**
(`https://github.com/piraeusdatastore/piraeus-operator/releases/download/v2.10.7/manifest.yaml`).
piraeus-operator publishes no anonymously-pullable Helm chart (the upstream install
method is `kubectl apply --server-side -f manifest.yaml`), so this component is
delivered as raw manifests (`kind: manifests`) — the **non-CRD** objects extracted
from the release manifest via `yq 'select(.kind != "CustomResourceDefinition")'`.
Nothing is hand-edited: no `replicaCount` pin, no consumer-specific values, no
invented pod labels.

## What ships

`manifests/00-namespace.yaml` — the `piraeus-datastore` Namespace; and
`manifests/10-operator.yaml` — everything else:

- **Deployment `piraeus-operator-controller-manager`** (ns `piraeus-datastore`,
  image `quay.io/piraeusdatastore/piraeus-operator:v2.10.7`) — the operator
  controller. Metrics are disabled (`--metrics-bind-address=0`); there is no
  metrics Service.
- **Deployment `piraeus-operator-gencert`** (ns `piraeus-datastore`, same image) —
  self-manages the webhook TLS material (see below).
- **Service `piraeus-operator-webhook-service`** (ns `piraeus-datastore`,
  port 443 → targetPort 9443) — backs the validating webhook.
- **ValidatingWebhookConfiguration
  `piraeus-operator-validating-webhook-configuration`** — validates StorageClass
  and the Linstor CRs; `failurePolicy: Fail`.
- **ConfigMap `piraeus-operator-image-config`** (ns `piraeus-datastore`) — bakes
  the default component image versions (linstor-server **v1.33.3**, linstor-csi
  v1.11.2, drbd-reactor, drbd-module-loader, …) from upstream v2.10.7.
- **ServiceAccounts, Roles/ClusterRoles, RoleBindings/ClusterRoleBindings** for the
  controller-manager and gencert.

**Zero CustomResourceDefinition objects** — the CRD schemas ship in
`storage-block/piraeus-operator-crds`, not here (strict-B workload half).

## Namespace & Pod Security Admission

`piraeus-datastore` ships with `pod-security.kubernetes.io/enforce: privileged`
(verbatim from upstream). This level is **required** because the operator
dynamically creates privileged DRBD/LINSTOR **satellite** DaemonSets at runtime —
those satellite pods are operator-created from a consumer's `LinstorCluster` CR and
are NOT part of this manifest. The operator's **own** pods (controller-manager,
gencert) are **hardened but below the PSA `restricted` profile**: they set
`runAsNonRoot: true` at the pod level and `allowPrivilegeEscalation: false` +
`readOnlyRootFilesystem: true` on every container, but the upstream manifest sets
**no** `seccompProfile: RuntimeDefault` and **no** `capabilities.drop: [ALL]`, both
of which `restricted` requires. They are therefore `baseline`-compatible, not
`restricted`-compatible. These fields are absent from the verbatim vendored
manifest and are not patched in here; the namespace posture is in any case dictated
by the satellite pods the operator will later place there.

This component is the **sole catalog occupant** of `piraeus-datastore` (dedicated
namespace), so it ships the `Namespace` object; a shipped manifest takes precedence
over Argo `managedNamespaceMetadata`, making the PSA posture authoritative. The
`-crds` half ships no Namespace.

## Webhook readiness (failurePolicy: Fail)

The `ValidatingWebhookConfiguration` uses `failurePolicy: Fail`. Webhook TLS is
**self-managed** by the `piraeus-operator-gencert` Deployment: it generates and
writes the `webhook-server-cert` Secret and patches the webhook's `caBundle` —
**no cert-manager dependency**. (The controller-manager ClusterRole carries
`cert-manager.io` verbs only for *optional* integration when a consumer runs
cert-manager; it is not required, and `secrets/cert-manager` is not an
`external_dependency`.)

> **Consumer obligation:** wait for the `piraeus-operator-gencert` pod to become
> Ready (the `caBundle` patched) before applying any `LinstorCluster` /
> `LinstorSatelliteConfiguration` CRs. With `failurePolicy: Fail`, the webhook
> rejects those CRs until its TLS is in place.

The webhook also validates **`StorageClass`** objects (`vstorageclass.kb.io`) and
carries no `namespaceSelector`/`objectSelector`, so during the boot window — after
Argo applies the `ValidatingWebhookConfiguration` but before the controller-manager
pod is Ready and gencert has patched the `caBundle` — any cluster-wide `StorageClass`
CREATE/UPDATE is rejected too. Consumers SHOULD therefore order any other Argo
Application that creates `StorageClass` objects (a sibling CSI such as
`storage-block/democratic-csi`, or consumer `StorageClass` CRs) into a **higher
sync-wave** (≥ 1) than this operator (wave 0), so those applies do not land inside
the operator's webhook boot window.

## Image versions

The `piraeus-operator-image-config` ConfigMap bakes the upstream v2.10.7 defaults
(linstor-server **v1.33.3** and the other component images). A consumer that needs
a different linstor-server (or other component) version applies a **consumer-layer
Kustomize patch** to that ConfigMap in the consumer-cluster repo — the catalog
ships the upstream default and bakes no image override here. A different baked
default would require a new vendored manifest (a separate reviewed change).

## RBAC scope (security note)

The ClusterRole `piraeus-operator-controller-manager` is intentionally broad: it
grants create/delete/get/list/patch/update/watch on
`apiextensions.k8s.io/customresourcedefinitions` and on
`rbac.authorization.k8s.io` `clusterrolebindings`/`clusterroles`/`rolebindings`/
`roles`. This is **intrinsic to the operator pattern** — the operator dynamically
creates the satellite DaemonSets and their RBAC. It cannot be narrowed without
breaking the operator; it is documented here for the security reviewer and kept
verbatim from upstream.

**Accepted risk (by design):** a compromise of the operator pod could write
arbitrary `ClusterRole`/`ClusterRoleBinding` objects (CWE-269, privilege
escalation). This grant is upstream-intrinsic and consciously accepted. Consumers
SHOULD confine the operator's Argo Application to the `piraeus-datastore` namespace
and MAY run a cluster admission policy (e.g. a Kyverno `restrict-clusteradmin`
rule) so the operator cannot bind itself cluster-admin.

## Consumer-required CRs (post-deploy, consumer-owned)

After this operator is healthy, consumers author a **`LinstorCluster`** CR (and
optionally **`LinstorSatelliteConfiguration`** CRs) against the `-crds` schemas to
bring up the LINSTOR storage cluster. These CRs are **consumer-owned** — they live
in the consumer-cluster repo overlay, not in this catalog component. They are not a
freeze-line `selector_crs` shape: the operator reconciles them via its controller
loop, it does not render a label selector against them.

> **Hardware prerequisite (consumer/base):** replicated DRBD storage needs the DRBD
> kernel module on the nodes (a Talos system-extension / machine-config concern in
> the substrate layer), independent of this catalog artifact.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app
**before** this workload:

1. **`storage-block/piraeus-operator-crds`** at
   `argocd.argoproj.io/sync-wave: "-1"` with
   `sync-options: Prune=false,ServerSideApply=true` (CR-cascade protection +
   the large-CRD annotation-limit workaround).
2. **`storage-block/piraeus-operator`** (this artifact) at sync-wave 0, which then
   comes up against CRDs that already exist.

## crd-bearing pairing

This workload carries **0 CRDs** — the strict-B gate's oracle asserts
`kind: CustomResourceDefinition` count **== 0** here and **> 0** in the
`crd-bearing: true` half (`storage-block/piraeus-operator-crds`).

## Capability

Provides `block-storage-replicated` at `swap_class: data-migration` — present in
`catalog/capability-index.yaml` with piraeus-operator as the active implementation.
Replacing the replicated-block backend is a data migration, not a drop-in. (The
`-crds` half is apis-only with no capability — the schema is the API surface, the
operational capability lives here.)

## Sync-wave

`0` — the operator workload lands after its CRD half (wave -1).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-block/piraeus-operator:vX.Y.Z
```

The git tag is `storage-block/piraeus-operator-vX.Y.Z`; `task push` strips the
leading `v`, so the OCI registry tag is the bare SemVer.

## Related ADRs

- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0018 — Policy Stack (Conftest)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md)
