# Component `secrets/external-secrets-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the
[External Secrets Operator](https://external-secrets.io/). It ships **only** the 23
`external-secrets.io` / `generators.external-secrets.io` CustomResourceDefinitions —
the External Secrets Operator workload (Deployment, RBAC, webhooks) is a **separate**
component, `secrets/external-secrets`. The two together form the strict-B pair: CRDs
first (this artifact, sync-wave -1), operator after (sync-wave 0).

The CRDs are sourced verbatim from the upstream `external-secrets` Helm chart
**2.5.0** (appVersion `v2.5.0`). The chart renders its CRDs as
`installCRDs`-gated chart templates (not a dedicated CRDs-only chart), so this
component is delivered as **raw vendored manifests** (`kind: manifests`) extracted
once from the chart, not as a Helm reference — there is no separate CRDs-only chart.

## What ships

Exactly 23 cluster-scoped CustomResourceDefinitions, in two API groups:

**`external-secrets.io` (6):**

- `clusterexternalsecrets.external-secrets.io`
- `clusterpushsecrets.external-secrets.io`
- `clustersecretstores.external-secrets.io`
- `externalsecrets.external-secrets.io`
- `pushsecrets.external-secrets.io`
- `secretstores.external-secrets.io`

**`generators.external-secrets.io` (17):**

- `acraccesstokens.generators.external-secrets.io`
- `cloudsmithaccesstokens.generators.external-secrets.io`
- `clustergenerators.generators.external-secrets.io`
- `ecrauthorizationtokens.generators.external-secrets.io`
- `fakes.generators.external-secrets.io`
- `gcraccesstokens.generators.external-secrets.io`
- `generatorstates.generators.external-secrets.io`
- `githubaccesstokens.generators.external-secrets.io`
- `grafanas.generators.external-secrets.io`
- `mfas.generators.external-secrets.io`
- `passwords.generators.external-secrets.io`
- `quayaccesstokens.generators.external-secrets.io`
- `sshkeys.generators.external-secrets.io`
- `stssessiontokens.generators.external-secrets.io`
- `uuids.generators.external-secrets.io`
- `vaultdynamicsecrets.generators.external-secrets.io`
- `webhooks.generators.external-secrets.io`

The `githubaccesstokens.generators.external-secrets.io` CRD (the `GithubAccessToken`
generator) is **required** — the consumer-side GHCR-token refresh path depends on it
([ADR-0025](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md)).

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD schemas.
The External Secrets Operator Namespace (with its Pod Security Admission `enforce`
label) stays with the `secrets/external-secrets` workload artifact; CRDs are
cluster-scoped and require no namespace.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the operator:

1. **`secrets/external-secrets-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting a CRD (and cascading the consumer's live `ExternalSecret` /
     `SecretStore` / `PushSecret` CRs, which would tear down the synced Secrets and
     the secret-sync wiring) when the source removes it. The Helm-layer
     `helm.sh/resource-policy: keep` annotation is **not** honored by Argo for its
     own prune decisions, so `Prune=false` carries the guarantee.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit — the External Secrets Operator CRDs are large — and is the convention
     for the strict-B `-crds` apps.

2. The workload Application **`secrets/external-secrets`** at sync-wave 0, which then
   comes up against CRDs that already exist (the `external-secrets.io` and
   `generators.external-secrets.io` API groups are registered).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`secrets/external-secrets`.

## Regeneration / drift

The vendored manifest (`manifests/00-external-secrets-crds.yaml`) was generated once
from chart `external-secrets` 2.5.0 via:

```sh
dom="external-secrets"
helm template es "$dom" \
  --repo "https://charts.${dom}.io" \
  --version 2.5.0 --namespace "$dom" --skip-tests \
  --set installCRDs=true \
  | yq -y 'select(.kind == "CustomResourceDefinition")'
```

The source chart+version (external-secrets 2.5.0) is the **drift anchor**. A chart
version bump requires re-vendoring this file **and** a `secrets/external-secrets-crds`
version bump. It MUST be bumped **together** with the `secrets/external-secrets`
workload chart pin — the workload chart version and this vendored-CRD anchor are
coupled (both `external-secrets 2.5.0` today). No mechanical drift check exists,
consistent with the `databases/cnpg-crds` and `network/multus-cni-crds` README-only
precedent; the coupling is upheld by convention and review.

When this artifact is bumped to a newer chart whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because the
consumer app runs `Prune=false`, fields the upstream removes are **not** auto-pruned
from the cluster; removal needs manual intervention. A version bump is a separate
reviewed change.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The `external-secrets.io`
and `generators.external-secrets.io` CRDs are the API surface (schemas), not a
swappable operational capability. The swappable capability `secret-sync` (declarative
external-secret synchronisation) is provided by the workload artifact
`secrets/external-secrets` (the controller that reconciles the `ExternalSecret` /
`SecretStore` / `PushSecret` / generator CRs), not by the CRD schemas alone
(precedent: `databases/cnpg-crds` and `network/multus-cni-crds`, likewise
api-surface-only with the capability on their workload counterpart). The
`provides[].api_surface` entries pin the representative served surfaces
`external-secrets.io/ExternalSecret@v1` (the primary CRD kind) and
`generators.external-secrets.io/GithubAccessToken@v1alpha1` (the ADR-0025 generator).

## Sync-wave

`-1` — the CRDs land before the operator workload at wave 0, so the
`external-secrets.io` and `generators.external-secrets.io` API groups are registered
before the operator starts reconciling `ExternalSecret` CRs.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/external-secrets-crds:vX.Y.Z
```

The git tag is `secrets/external-secrets-crds-vX.Y.Z` (first release `v0.1.0`);
`task push` strips the leading `v`, so the OCI registry tag is the bare SemVer. The
workload `secrets/external-secrets` carries
`requires: {secrets/external-secrets-crds: ">=v0.1.0"}` and `installCRDs: false` (its
companion strict-B refactor) — it renders zero CRDs and depends on this artifact
landing first at wave -1.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0025 — ArgoCD credentials, no PAT](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
