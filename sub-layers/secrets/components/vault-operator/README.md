# Component `secrets/vault-operator`

The **strict-B WORKLOAD artifact** (talos-platform-docs ADR-0028) for the
[Bank-Vaults Vault Operator](https://github.com/bank-vaults/vault-operator) (Helm
`oci://ghcr.io/bank-vaults/helm-charts/vault-operator`, chart 1.24.0). It ships
the **CRD-free operator** — Deployment + RBAC + Service — that reconciles the
`Vault` CR (`vault.banzaicloud.com`), declaratively managing Vault instances in
the cluster.

The Vault CustomResourceDefinition (`vaults.vault.banzaicloud.com`) is a
**separate** component, `secrets/vault-operator-crds` (sync-wave -1). The two
together form the strict-B pair: CRD first, operator after. This workload artifact
renders `crds.install: false`, so it carries **0** `CustomResourceDefinition`
resources.

This workload **requires** the `secrets/vault-operator-crds` artifact: the
operator reconciles the `Vault` CR, so the CRD MUST be established first (strict-B
ordering, ADR-0028).

## Contents

- `helm/vault-operator.yaml` — Vault Operator chart reference (chart 1.24.0,
  `crds.install: false`) + slim default values. The chart is an **OCI** chart, so
  the `oci://` reference is the `chart` value and `repo` is empty.
- `manifests/00-namespace.yaml` — the dedicated `vault-operator` Namespace
  carrying the PSA `enforce` label (sole-claimant rule, ADR-0027).

## Namespace & Pod Security

The operator occupies the **dedicated** `vault-operator` namespace and is its sole
catalog occupant, so this component ships the `Namespace` object (a shipped
manifest is authoritative over Argo `managedNamespaceMetadata`). The namespace
carries `pod-security.kubernetes.io/enforce: restricted` — the operator Deployment
is provably `restricted`-compliant (pod `runAsNonRoot` + `seccompProfile:
RuntimeDefault`; the single container `allowPrivilegeEscalation: false` +
`readOnlyRootFilesystem: true` + `capabilities.drop: [ALL]`; the image runs as a
non-root UID). The `bank-vaults` helper (`v1.33.1`) is **not** a sidecar on the
operator pod — it is the image the operator injects into the Vault pods it manages,
so the operator pod has a single container.

The catalog ships **only** the `enforce` level plus the
`platform.devoba.de/{sub-layer,component}` labels. Per ADR-0027, the **consumer**
adds, in its Argo overlay:

- `pod-security.kubernetes.io/enforce-version` — pinned to the consumer cluster's
  Kubernetes minor (a cluster property, not a catalog default), and
- any PNI labels (`platform.io/provide.*`, `consume.*`, `network-profile`) —
  these are consumer-composition concerns.

## Cluster-wide RBAC

The chart ships a `ClusterRole` + `ClusterRoleBinding` granting the operator
**cluster-wide** `verbs: ["*"]` on core `secrets` (and on `apps`
`deployments`/`statefulsets`). This is the **upstream chart default** and is
functionally required: the operator provisions `Vault` instances together with
their TLS, unseal, and token `Secrets` in **arbitrary consumer namespaces**, so
the grant **cannot** be narrowed without forking the chart RBAC. The catalog
**accepts** this grant for that reason.

The blast radius is a **known property** of this operator pattern: a compromised
operator can read, write, and delete `Secrets` cluster-wide. A future hardening
option, if a consumer constrains where `Vault` CRs may run, is to confine the
operator to a fixed namespace set and narrow the `ClusterRole` accordingly; this
is **out of scope** for the catalog default and would be a consumer-side
composition concern.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app
**before** this operator:

1. **`secrets/vault-operator-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   `Prune=false` is the authoritative CR-cascade protection (it stops Argo from
   deleting the CRD and cascading the consumer's live `Vault` CRs, tearing down
   the managed Vault instances). `ServerSideApply=true` clears the 262 KB
   client-side annotation limit on the large Vault CRD.

2. **`secrets/vault-operator`** (this workload) Application at
   `argocd.argoproj.io/sync-wave: "0"`, which then comes up against a CRD that
   already exists (the `vault.banzaicloud.com` API group is registered).

## Sync-wave

`0` — the operator lands after the CRD half (`secrets/vault-operator-crds`, wave
-1).

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/vault-operator:vX.Y.Z
```

The git tag is `secrets/vault-operator-vX.Y.Z` (first release `v0.1.0`);
`task push` strips the leading `v`, so the OCI registry tag is the bare SemVer.

## Capability

Provides `vault-secrets` (id `vault-secrets`, `swap_class: data-migration`) — the
controller that reconciles the `Vault` CR for declarative Vault instance
management. The active implementation of `vault-secrets` in
`catalog/capability-index.yaml` is this component; swapping away requires migrating
the stored secret data (hence `data-migration`). The CRD schema
(`vault.banzaicloud.com/Vault`) is the api-surface of the `-crds` half.

## Out of scope

- The `Vault` CR instance (storage backend, unseal config, HA, TLS, auth engines)
  — consumer-authored, never shipped in this catalog.
- `vault-config-operator` — a separate operator (`redhatcop.redhat.io` CRDs,
  declarative Vault config), covered by a distinct component.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0011 — Secrets-Management (SOPS + Layer-3 Vault)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0027 — Namespace / PSA ownership model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0027-namespace-psa-ownership.md)
