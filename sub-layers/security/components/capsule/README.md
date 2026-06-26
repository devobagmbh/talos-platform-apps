# Component `security/capsule`

The **strict-B WORKLOAD artifact** (talos-platform-docs ADR-0028) for
[Capsule](https://projectcapsule.github.io/capsule/) — the multi-tenancy operator that
implements namespace-level tenant isolation in Kubernetes. It ships the **Capsule
controller-manager workload** (the `capsule-controller-manager` Deployment + operator
RBAC + Services + admission webhook configuration + the dedicated `capsule-system`
Namespace) and carries **zero CRDs**; the 11 `capsule.clastix.io`
`CustomResourceDefinition` objects ship in the **separate** strict-B CRD half,
[`security/capsule-crds`](../capsule-crds/README.md). The two together form the strict-B
pair: CRDs first (sync-wave -1), workload after (sync-wave 0).

Helm chart `capsule` from `https://projectcapsule.github.io/charts`, pinned to
**0.13.7** (appVersion **v0.13.7**, controller image
`ghcr.io/projectcapsule/capsule:v0.13.7`).

## What ships

- **`manifests/00-namespace.yaml`** — the `capsule-system` Namespace with
  `pod-security.kubernetes.io/enforce: restricted` (sole claimant, see PSA below).
- **`helm/capsule.yaml`** — Helm values rendering the controller-manager workload with
  `crds.install: false` (0 CRDs) and hardened security contexts pinned explicitly.

The rendered workload (`rendered/manifest.yaml`) includes:

- **`Deployment` `capsule-controller-manager`** (ns `capsule-system`, image
  `ghcr.io/projectcapsule/capsule:v0.13.7`) — the operator. Reconciles `Tenant`,
  `CapsuleConfiguration`, and related `capsule.clastix.io` CRs and dynamically manages
  the `ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration` objects at
  cluster runtime.
- **`ServiceAccount` `capsule`** (ns `capsule-system`) — operator identity.
- **`ClusterRole` + `ClusterRoleBinding` `capsule-namespace-deleter`** and
  **`capsule-namespace-provisioner`** — operator RBAC for namespace lifecycle.
- **`Service` `capsule-webhook-service`** (ns `capsule-system`) and
  **`Service` `capsule-controller-manager-metrics-service`** (ns `capsule-system`).
- **`CapsuleConfiguration` `default`** (ns `capsule-system`) — the operator's
  configuration singleton (a catalog default, see below).
- **`Certificate`** + **`Issuer`** (cert-manager resources) — the self-signed TLS
  bundle for the webhook service.
- **Pre-delete `Job`** + supporting `ServiceAccount` / `ClusterRole` / `ClusterRoleBinding`
  / `Role` / `RoleBinding` (Helm hook, removes TLS secret and ClusterRoles on uninstall).

**Zero `CustomResourceDefinition` objects** — the 11 CRD schemas ship in
`security/capsule-crds`, not here (strict-B workload half).

## The `CapsuleConfiguration` CR — a catalog default

The `CapsuleConfiguration` CR named `default` ships as a catalog default (equivalent to
the kubevirt `KubeVirt` CR precedent). The controller reads it to determine the webhook
service name, TLS secret references, RBAC role names, and admission user groups. The
shipped defaults are cluster-agnostic and fully operational as-is. A consumer who needs
to diverge (e.g. add custom `users`/`administrators` groups, or tune RBAC role names)
patches the CR via their own Argo overlay — that is not a freeze-line shape.

## Namespace & Pod Security Admission

`capsule-system` ships with `pod-security.kubernetes.io/enforce: restricted`. The
controller-manager pod is **fully hardened** and provably satisfies every `restricted`
PSS control:

- **pod-level** (`podSecurityContext`): `runAsNonRoot: true`, `runAsUser: 1002`,
  `runAsGroup: 1002`, `seccompProfile.type: RuntimeDefault`.
- **container-level** (`securityContext`): `allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true`. No `privileged: true`,
  no `hostNetwork`, no `hostPath` volumes, no host ports.

These values are derived from the rendered manifest (`rendered/manifest.yaml`) with
chart values `podSecurityContext.enabled: true` and `securityContext.enabled: true`
(chart 0.13.7 defaults, pinned explicitly in `helm/capsule.yaml` to prevent a silent
future flip on upgrade). `restricted` is the strictest level the workload provably
satisfies; it must not be relaxed without re-deriving from the rendered securityContext.

This component is the **sole catalog occupant** of `capsule-system` (dedicated
namespace), so it ships the `Namespace` object; a shipped manifest takes precedence over
Argo `managedNamespaceMetadata`, making the PSA posture authoritative. The `-crds` half
ships no Namespace.

## Webhook bootstrap safety — no capsule-system self-wedge

The Capsule chart v0.13.7 does **not** render standalone `ValidatingWebhookConfiguration`
/ `MutatingWebhookConfiguration` objects in the Helm output. Instead, it renders a
`CapsuleConfiguration` CR (a `capsule.clastix.io/v1beta2` resource) that embeds the
webhook spec; the running controller-manager creates and manages the actual
`ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration` objects at runtime
once it is healthy.

All tenant-scoped webhook rules in the `CapsuleConfiguration` use a
`namespaceSelector: matchExpressions: [{key: capsule.clastix.io/tenant, operator:
Exists}]` guard — they fire **only in namespaces labelled as Capsule tenant namespaces**.
The `capsule-system` namespace itself is **not** a tenant namespace and carries no such
label, so:

1. **The webhook cannot intercept traffic in its own bootstrap namespace.** Pod/namespace
   creation in `capsule-system` is never routed to the Capsule admission endpoint, even
   before the TLS certificate is available.
2. **CapsuleConfiguration is a Cluster-scoped resource** — the Capsule validating/mutating
   hooks that act on `capsule.clastix.io` CRs (Tenant, TenantOwner, ResourcePool, etc.)
   do not use a `namespaceSelector` restricted to `capsule-system`, but they match on the
   `capsule.clastix.io` API group only — not on the `capsule-system` namespace bootstrap
   path (namespace and pod CREATE in `capsule-system`).
3. The `config.validating.projectcapsule.dev` hook (for `CapsuleConfiguration` updates)
   uses `failurePolicy: Ignore` — a degraded controller cannot block its own
   configuration update.
4. The `managed.validating.projectcapsule.dev` hook also uses `failurePolicy: Ignore`.
   All other tenant-scoped hooks use `failurePolicy: Fail`, but since `capsule-system`
   is excluded by the namespace selector, this does not affect bootstrap.

**Conclusion:** on a fresh install, the Capsule admission hooks cannot wedge the
`capsule-system` namespace bootstrap. The controller-manager starts, obtains its
TLS certificate (via cert-manager), and then installs the runtime webhook
configurations — at which point only tenant-scoped traffic is intercepted.

## Freeze-line (ADR-0024)

The **workload** (controller-manager Deployment + RBAC + Services + webhook
configuration + CapsuleConfiguration CR) is the signed, pre-rendered artifact.
The operator is **cluster-agnostic at the freeze line**: it reconciles Tenant CRs from
the CRD API without any cluster-specific env, secret, or ConfigMap mounted by the
controller-manager pod. All six freeze-line keys in `customization.yaml` are empty —
this is NOT a hollow pass but the accurate state:

- No `env_keys` — no cluster-specific env scalars; the two `env` vars are downward-API
  fields (`metadata.namespace`, `spec.serviceAccountName`) injected by Kubernetes, not
  consumer-supplied.
- No `config_files` — no mounted ConfigMap; the operator reads its configuration from
  the `CapsuleConfiguration` CR (a catalog default, not a freeze-line shape).
- No `secret_keys` — the TLS secret (`capsule-tls`) is cert-manager-issued and
  consumed internally; it is not a consumer-supplied runtime secret.
- No `selector_crs` — the controller watches `Tenant` CRs via its reconcile loop, not
  via a label selector on consumer-labelled objects.

Concrete `Tenant` and `CapsuleConfiguration` CRs are consumer-owned and live in the
consumer cluster repos.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app **before**
this workload:

1. **`security/capsule-crds`** at `argocd.argoproj.io/sync-wave: "-1"` with
   `sync-options: Prune=false,ServerSideApply=true` (CRD cascade protection + large-CRD
   annotation-limit workaround).
2. **`security/capsule`** (this artifact) at sync-wave 0, which renders against CRDs
   that already exist.

## crd-bearing pairing

This workload carries **0 CRDs** — the strict-B gate's oracle asserts
`kind: CustomResourceDefinition` count **== 0** here and **> 0** in the `crd-bearing: true`
half (`security/capsule-crds`).

## Capability

Provides `namespace-tenancy` at `swap_class: rewrite-required` — present in
`catalog/capability-index.yaml` with capsule as the active implementation. Replacing the
multi-tenancy operator means rewriting every consumer `Tenant` CR against a different
tool's schema (e.g. kiosk), not a drop-in. (The `-crds` half is api-surface-only with
no capability — the schema is the API surface, the operational capability lives here in
the operator that reconciles `Tenant` CRs into namespace isolation policies.)

## Sync-wave

`0` — the operator workload lands after its CRD half (wave -1).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/security/capsule:vX.Y.Z
```

The git tag is `security/capsule-vX.Y.Z`; `task push` strips the leading `v`, so the
OCI registry tag is the bare SemVer (the component name is the OCI *path*, not the tag).

## Related ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0037 — Multi-Tenancy/Capsule](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0037-multi-tenancy.md)
