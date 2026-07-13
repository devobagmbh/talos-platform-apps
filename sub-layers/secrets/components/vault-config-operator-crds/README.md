# Component `secrets/vault-config-operator-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the
[Vault Config Operator](https://github.com/redhat-cop/vault-config-operator). It
ships **only** the 47 `redhatcop.redhat.io` CustomResourceDefinitions — the
operator workload (Deployment, RBAC, webhooks) is a **separate** component,
`secrets/vault-config-operator`. The two together form the strict-B pair: CRDs
first (this artifact, sync-wave -1), operator after (sync-wave 1).

The CRDs are sourced verbatim from the upstream `vault-config-operator` Helm
chart **v0.8.49** (appVersion `v0.8.49`). The chart delivers its CRDs from the
chart `crds/` directory (the Helm CRD-lifecycle path), which `helm template`
does not render without `--include-crds`. This component is therefore delivered
as **raw vendored manifests** (`kind: manifests`) extracted once from the
chart's `crds/` directory, not as a Helm reference.

## What ships

Exactly **47** cluster-scoped CustomResourceDefinitions, all in the single API
group **`redhatcop.redhat.io`** (served version `v1alpha1`). The CRD kinds are:

`Audit`, `AuditRequestHeader`, `AuthEngineMount`, `AzureAuthEngineConfig`,
`AzureAuthEngineRole`, `AzureSecretEngineConfig`, `AzureSecretEngineRole`,
`CertAuthEngineConfig`, `CertAuthEngineRole`, `DatabaseSecretEngineConfig`,
`DatabaseSecretEngineRole`, `DatabaseSecretEngineStaticRole`, `Entity`,
`EntityAlias`, `GCPAuthEngineConfig`, `GCPAuthEngineRole`,
`GitHubSecretEngineConfig`, `GitHubSecretEngineRole`, `Group`, `GroupAlias`,
`IdentityOIDCAssignment`, `IdentityOIDCClient`, `IdentityOIDCProvider`,
`IdentityOIDCScope`, `IdentityTokenConfig`, `IdentityTokenKey`,
`IdentityTokenRole`, `JWTOIDCAuthEngineConfig`, `JWTOIDCAuthEngineRole`,
`KubernetesAuthEngineConfig`, `KubernetesAuthEngineRole`,
`KubernetesSecretEngineConfig`, `KubernetesSecretEngineRole`,
`LDAPAuthEngineConfig`, `LDAPAuthEngineGroup`, `PasswordPolicy`,
`PKISecretEngineConfig`, `PKISecretEngineRole`, `Policy`,
`QuaySecretEngineConfig`, `QuaySecretEngineRole`, `QuaySecretEngineStaticRole`,
`RabbitMQSecretEngineConfig`, `RabbitMQSecretEngineRole`, `RandomSecret`,
`SecretEngineMount`, `VaultSecret`.

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD
schemas. The Vault Config Operator Namespace (with its Pod Security Admission
`enforce` label) stays with the `secrets/vault-config-operator` workload
artifact; CRDs are cluster-scoped and require no namespace.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the operator:

1. **`secrets/vault-config-operator-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting a CRD (and cascading the consumer's live `VaultSecret` /
     `KubernetesAuthEngineRole` / `SecretEngineMount` CRs, which would tear down
     the declarative Vault configuration) when the source removes it. The
     Helm-layer `helm.sh/resource-policy: keep` annotation is **not** honored by
     Argo for its own prune decisions, so `Prune=false` carries the guarantee.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit — several of these CRDs are large — and is the convention for the
     strict-B `-crds` apps.

2. The workload Application **`secrets/vault-config-operator`** at sync-wave 1,
   which then comes up against CRDs that already exist (the `redhatcop.redhat.io`
   API group is registered).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`secrets/vault-config-operator`.

## Regeneration / drift

The vendored manifest (`manifests/00-vault-config-operator-crds.yaml`) was
generated once from chart `vault-config-operator` v0.8.49 via:

```sh
helm pull vault-config-operator \
  --repo https://redhat-cop.github.io/vault-config-operator/ \
  --version v0.8.49 --untar
yq eval-all 'select(.kind == "CustomResourceDefinition")' \
  vault-config-operator/crds/*.yaml \
  > manifests/00-vault-config-operator-crds.yaml
```

The source chart+version (`vault-config-operator` v0.8.49) is the **drift
anchor**, recorded here as the **47-CRD** count to re-verify at the next bump. A
chart version bump requires re-vendoring this file **and** a
`secrets/vault-config-operator-crds` version bump. It MUST be bumped **together**
with the `secrets/vault-config-operator` workload chart pin — the workload chart
version and this vendored-CRD anchor are coupled (both `v0.8.49` today). No
mechanical drift check exists, consistent with the `secrets/external-secrets-crds`
and `databases/cnpg-crds` README-only precedent; the coupling is upheld by
convention and review.

When this artifact is bumped to a newer chart whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because
the consumer app runs `Prune=false`, fields the upstream removes are **not**
auto-pruned from the cluster; removal needs manual intervention. A version bump
is a separate reviewed change.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The
`redhatcop.redhat.io` CRDs are the API surface (schemas), not a swappable
operational capability. The swappable capability `secret-config-declarative`
(declarative Vault configuration) is provided by the workload artifact
`secrets/vault-config-operator` (the controller that reconciles the
`VaultSecret` / `KubernetesAuthEngineRole` / `SecretEngineMount` CRs), not by the
CRD schemas alone (precedent: `secrets/external-secrets-crds` and
`databases/cnpg-crds`, likewise api-surface-only with the capability on their
workload counterpart). The `provides[].api_surface` entries pin the
representative served surfaces `redhatcop.redhat.io/Policy@v1alpha1`,
`redhatcop.redhat.io/SecretEngineMount@v1alpha1`, and
`redhatcop.redhat.io/KubernetesAuthEngineRole@v1alpha1`.

## Sync-wave

`-1` — the CRDs land before the operator workload at wave 1, so the
`redhatcop.redhat.io` API group is registered before the operator starts
reconciling its CRs.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/vault-config-operator-crds:vX.Y.Z
```

The git tag is `secrets/vault-config-operator-crds-vX.Y.Z` (first release
`v0.1.0`); `task push` strips the leading `v`, so the OCI registry tag is the
bare SemVer. The workload `secrets/vault-config-operator` carries
`requires: {secrets/vault-config-operator-crds: ">=v0.1.0"}` — it renders zero
CRDs and depends on this artifact landing first at wave -1.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
