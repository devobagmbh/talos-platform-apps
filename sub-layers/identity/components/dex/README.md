# Component `identity/dex`

[Dex](https://dexidp.io/) — the cluster's **OIDC identity broker** (capability
`identity-oidc`, [ADR-0010](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)).
Every app with a login authenticates against dex; dex federates the EntraID
tenant upstream. Migrated from `talos-platform-base/kubernetes/base/infrastructure/dex/`
per the v1.0.0 substrate split (base#90).

## Why a broker (not direct-to-EntraID)

One OIDC plumbing per cluster: every relying app (`argocd`, `harbor`, `crossview`,
`kubelogin`, …) is a dex `staticClient`; only dex talks to EntraID. Two
independent dex instances run platform-wide (one per cluster) so an auth outage in
one cluster never kills login in the other. The per-app OIDC binding is documented
in each consumer app (e.g. `registry/harbor` § "Dex / OIDC SSO").

## Contents

| Resource | Function |
|---|---|
| `Namespace dex` | Component boundary. PSA `baseline` enforce / `restricted` audit+warn. |
| dex chart (`dexidp/dex` 0.24.0) | Deployment (2 replicas + PDB), Service (ClusterIP), ServiceAccount + RBAC. |

The workload is **restricted-PSA-compliant** (drop ALL caps, `readOnlyRootFilesystem`,
`runAsNonRoot`, writable `/tmp` emptyDir only).

## Consumer-supplied config (Shape c)

The catalog ships **no dex config and no secrets**. The chart is rendered with
`configSecret.create: false`, so the workload references an existing secret
**`dex-config`** (key `config.yaml`). The consumer creates it before sync — via
**SOPS** on the seeder (Vault not yet up) or **Vault + ESO** on office-lab — with a
`config.yaml` carrying:

```yaml
issuer: https://<dex-host>            # cluster-specific public URL (also the HTTPRoute host)
storage:
  type: kubernetes                    # or postgres — see "Storage" below
connectors:
  - type: oidc                        # the EntraID federation
    id: entraid
    name: EntraID
    config:
      issuer: https://login.microsoftonline.com/<tenant>/v2.0
      clientID: <entraid-app-client-id>
      clientSecret: <entraid-app-client-secret>   # sensitive → why this is Shape c
      redirectURI: https://<dex-host>/callback
oauth2:
  skipApprovalScreen: true
staticClients:                        # one per relying app (ADR-0010 roster)
  - id: argocd
    name: ArgoCD
    secret: <argocd-client-secret>
    redirectURIs: ["https://<argocd-host>/auth/callback"]
  # … harbor, crossview, kubelogin, …
```

Because the EntraID connector secret and every staticClient secret live **inside**
this one file, the whole config is a single Shape (c) secret — not a Shape (b)
merged config.

## Storage

`replicaCount: 2` (HA, migrated from base). With more than one replica the
consumer's `config.yaml` **must** use a shared backend — `storage.type: kubernetes`
(dex CRDs, RBAC is shipped) or `postgres` (the `cnpg-postgres` capability).
`storage.type: memory` is per-pod and breaks the OAuth2 code→token exchange across
replicas. The catalog leaves the choice to the consumer (it is config, not a chart
value); `memory` is acceptable only at `replicaCount: 1`.

## Consumer network

base#90 carried PNI labels (`platform.io/network-profile: managed`,
`platform.io/consume.{cnpg-postgres,gateway-backend,controlplane-egress}`) on the
namespace. Those are the consumer's network-layer contract (no apps component ships
them) — the consumer overlay adds them plus the **HTTPRoute** that fronts dex on
the Cilium Gateway (TLS terminates there; `https.enabled: false` in-pod).

## Sync-wave

`0` — foundational. Consumers order dex **before** its OIDC relying parties
(argocd/harbor/crossview SSO), so their Argo apps use a later wave.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/identity/dex:vX.Y.Z
```

## Related ADRs

- [ADR-0010 — Identity provider (dex federating EntraID)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)
- [ADR-0023 — Consumer-side value layering](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0023-value-layering.md)
- [ADR-0024 — Customization contract / workload-config freeze-line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md)
