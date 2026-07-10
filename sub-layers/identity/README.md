# Sub-layer `identity`

Cluster identity: the OIDC broker that every app with a login authenticates
against. The sub-layer is an organizational bracket; **OCI distribution is per
component** (ADR-0009). Each component has its own native OCI artifact
(pre-rendered manifests, single-layer), its own Argo `Application`, and an
independent lifecycle.

## Components

| Component | sync-wave | Content | OCI |
|---|---|---|---|
| [`dex`](components/dex/) | 0 | OIDC identity broker (`dexidp/dex`) federating EntraID; capability `identity-oidc` | `oci://.../identity/dex:vX.Y.Z` |

dex is **foundational**: consumers deploy it before its OIDC relying parties
(argocd / harbor / crossview SSO), which therefore use a later sync-wave in the
consumer cluster manifests.

## Capabilities

- `identity-oidc` — OIDC identity provider (ADR-0010). Implementations in the
  catalog index: `dex` (active); `keycloak`, `authelia` (considered). Swap class
  `label-move`.

## Consumed by

- A control-plane consumer — own dex instance (`argocd`, `harbor`,
  `kubelogin` static clients).
- A workload consumer — own dex instance (argocd, harbor, grafana, vault, kubelogin,
  alertmanager, kubevirt-manager static clients).

Each consumer runs its own dex instance, all federating the same EntraID tenant via
separate app registrations — an auth outage in one cluster never blocks login in
another.

## Render convention

Each component renders via `task render:one -- identity/<component>` to
`components/<component>/rendered/manifest.yaml`, then packaged + pushed per
component:

```bash
task render:one -- identity/dex
task publish    -- identity/dex v0.1.0
```

`task render -- identity` renders all components of this sub-layer.

## Related ADRs

- [ADR-0010 — Identity provider (dex federating EntraID)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)
- [ADR-0009 — Platform layer model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) (per-component OCI granularity)
- [ADR-0023 — Consumer-side value layering](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0023-value-layering.md)
- [ADR-0024 — Customization contract](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md)
