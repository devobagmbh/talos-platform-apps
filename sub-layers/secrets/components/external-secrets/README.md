# Component `secrets/external-secrets`

The **strict-B WORKLOAD artifact** (talos-platform-docs ADR-0028) for the
[External Secrets Operator](https://external-secrets.io/) (Helm
`external-secrets/external-secrets`, chart 2.5.0). It ships the **CRD-free ESO
operator** — Deployment + RBAC + webhooks — that reconciles `ExternalSecret` /
`SecretStore` / `PushSecret` / generator CRs, syncing secrets from Vault (Layer 3)
into Kubernetes Secrets and, via the **generators**, minting/refreshing provider
tokens.

The External Secrets Operator CustomResourceDefinitions (the `external-secrets.io`
and `generators.external-secrets.io` groups) are a **separate** component,
`secrets/external-secrets-crds` (sync-wave -1). The two together form the strict-B
pair: CRDs first, operator after. This workload artifact renders `installCRDs:
false`, so it carries **0** `CustomResourceDefinition` resources.

This workload **requires** the `secrets/external-secrets-crds` artifact: the
operator reconciles those CRs, so the CRDs MUST be established first (strict-B
ordering, ADR-0028).

## Contents

- `helm/external-secrets.yaml` — ESO chart reference (chart 2.5.0,
  `installCRDs: false`) + slim default values.
- `manifests/00-namespace.yaml` — the dedicated `external-secrets` Namespace
  carrying the PSA `enforce` label (sole-claimant rule, ADR-0027).

## Namespace & Pod Security

ESO occupies the **dedicated** `external-secrets` namespace and is its sole
catalog occupant, so this component ships the `Namespace` object (a shipped
manifest is authoritative over Argo `managedNamespaceMetadata`). The namespace
carries `pod-security.kubernetes.io/enforce: restricted` — every workload the
chart renders (the operator, webhook, and cert-controller Deployments) is
provably `restricted`-compliant (pod `runAsNonRoot` + `seccompProfile:
RuntimeDefault`; every container `allowPrivilegeEscalation: false` +
`capabilities.drop: [ALL]`).

The catalog ships **only** the `enforce` level plus the
`platform.devoba.de/{sub-layer,component}` labels. Per ADR-0027, the **consumer**
adds, in its Argo overlay:

- `pod-security.kubernetes.io/enforce-version` — pinned to the consumer cluster's
  Kubernetes minor (a cluster property, not a catalog default), and
- any PNI labels (`platform.io/provide.*`, `consume.*`, `network-profile`) —
  these are consumer-composition concerns.

## GithubAccessToken generator (ADR-0025)

The `GithubAccessToken` generator — used by a consumer to mint/refresh the
private-GHCR pull credential without a PAT
([ADR-0025](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md))
— is reconciled by **this** operator, but its CRD now ships in the
`secrets/external-secrets-crds` artifact. The consumer MUST deploy **both** apps
(the `-crds` half at wave -1 and this operator at wave 0) for that path to work.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app
**before** this operator:

1. **`secrets/external-secrets-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   `Prune=false` is the authoritative CR-cascade protection (it stops Argo from
   deleting a CRD and cascading the consumer's live `ExternalSecret` /
   `SecretStore` / `PushSecret` CRs). `ServerSideApply=true` clears the 262 KB
   client-side annotation limit on the large ESO CRDs.

2. **`secrets/external-secrets`** (this workload) Application at
   `argocd.argoproj.io/sync-wave: "0"`, which then comes up against CRDs that
   already exist (the `external-secrets.io` and `generators.external-secrets.io`
   API groups are registered).

## Sync-wave

`0` — the operator lands after the CRD half (`secrets/external-secrets-crds`, wave
-1). A consumer that depends on ESO at bootstrap (e.g. a GHCR token at bootstrap)
deploys it in an **earlier** wave (such a consumer uses `-10`), keeping the
`-crds` half one wave ahead.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/external-secrets:vX.Y.Z
```

## Consumed by

- A consumer whose Vault is remote — yes: the GHCR `GithubAccessToken` generator
  (ADR-0025) + later cross-cluster `ClusterSecretStore` to the remote Vault.
- A consumer whose Vault is in-cluster — yes: local Vault `ClusterSecretStore`
  (Kubernetes auth).

The Stage-0 bootstrap does **not** use ESO — only SOPS (+ the one-shot GHCR token
mint bridges until ESO is up).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0011 — Secrets-Management (SOPS + Layer-3 Vault)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0025 — ArgoCD credentials, no PAT (GithubAccessToken generator)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md)
- [ADR-0027 — Namespace / PSA ownership model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0027-namespace-psa-ownership.md)
