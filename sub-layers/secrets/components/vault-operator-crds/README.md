# Component `secrets/vault-operator-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the
[Bank-Vaults Vault Operator](https://github.com/bank-vaults/vault-operator). It
ships **only** the single `vault.banzaicloud.com` CustomResourceDefinition — the
operator workload (Deployment, RBAC) is a **separate** component,
`secrets/vault-operator`. The two together form the strict-B pair: CRD first
(this artifact, sync-wave -1), operator after (sync-wave 0).

The CRD is sourced verbatim from the upstream `vault-operator` Helm chart
**v1.24.0** (`oci://ghcr.io/bank-vaults/helm-charts/vault-operator`). In that
chart the CRD lives in the bundled `crds` sub-chart under `charts/crds/crds/`,
**not** under `templates/`, so `helm template` does not render it without
`--include-crds`. This component is therefore delivered as a **raw vendored
manifest** (`kind: manifests`) extracted once from the chart's CRD directory, not
as a Helm reference.

## What ships

Exactly **one** CustomResourceDefinition (its instances are namespace-scoped):

- `vaults.vault.banzaicloud.com` (group `vault.banzaicloud.com`, kind `Vault`,
  served version `v1alpha1`) — the Vault instance CR the operator reconciles.

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD
schema. The Vault Operator Namespace (with its Pod Security Admission `enforce`
label) stays with the `secrets/vault-operator` workload artifact.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the operator:

1. **`secrets/vault-operator-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRD (and cascading the consumer's live `Vault` CRs, which would
     tear down the managed Vault instances) when the source removes it. The
     Helm-layer `helm.sh/resource-policy: keep` annotation is **not** honored by
     Argo for its own prune decisions, so `Prune=false` carries the guarantee.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit — the Vault CRD is large — and is the convention for the strict-B
     `-crds` apps.

2. The workload Application **`secrets/vault-operator`** at sync-wave 0, which
   then comes up against a CRD that already exists (the `vault.banzaicloud.com`
   API group is registered).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`secrets/vault-operator`.

## Regeneration / drift

The vendored manifest (`manifests/00-vault-operator-crds.yaml`) was generated
once from chart `vault-operator` v1.24.0 via:

```sh
helm pull oci://ghcr.io/bank-vaults/helm-charts/vault-operator \
  --version 1.24.0 --untar
cp vault-operator/charts/crds/crds/vault.banzaicloud.com_vaults.yaml \
  manifests/00-vault-operator-crds.yaml   # leading '---' document marker stripped
```

The source chart+version (`vault-operator` v1.24.0) is the **drift anchor**,
recorded here as the **single-CRD** (`vaults.vault.banzaicloud.com`) count to
re-verify at the next bump. A chart version bump requires re-vendoring this file
**and** a `secrets/vault-operator-crds` version bump. It MUST be bumped
**together** with the `secrets/vault-operator` workload chart pin — the workload
chart version and this vendored-CRD anchor are coupled (both `v1.24.0` today). No
mechanical drift check exists, consistent with the
`secrets/vault-config-operator-crds` and `databases/cnpg-crds` README-only
precedent; the coupling is upheld by convention and review.

When this artifact is bumped to a newer chart whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because
the consumer app runs `Prune=false`, fields the upstream removes are **not**
auto-pruned from the cluster; removal needs manual intervention. A version bump
is a separate reviewed change.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The
`vault.banzaicloud.com` CRD is the API surface (the schema), not a swappable
operational capability. The swappable capability `vault-secrets` (declarative
Vault instance management) is provided by the workload artifact
`secrets/vault-operator` (the controller that reconciles the `Vault` CR), not by
the CRD schema alone (precedent: `secrets/vault-config-operator-crds` and
`databases/cnpg-crds`, likewise api-surface-only with the capability on their
workload counterpart). The `provides[].api_surface` entry pins the served surface
`vault.banzaicloud.com/Vault@v1alpha1`.

## Sync-wave

`-1` — the CRD lands before the operator workload at wave 0, so the
`vault.banzaicloud.com` API group is registered before the operator starts
reconciling its Vault CRs.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/vault-operator-crds:vX.Y.Z
```

The git tag is `secrets/vault-operator-crds-vX.Y.Z` (first release `v0.1.0`);
`task push` strips the leading `v`, so the OCI registry tag is the bare SemVer.
The workload `secrets/vault-operator` carries
`requires: {secrets/vault-operator-crds: ">=v0.1.0"}` — it renders zero CRDs and
depends on this artifact landing first at wave -1.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
