# Component `registry/harbor`

Harbor (Helm `harbor/harbor` 1.19.1, appVersion 2.15.1) — container registry + pull-through cache + OCI artifact store. Includes the Trivy scanner.

## Render profile (Tag 1: seeder pull-through cache)

The currently rendered profile targets the **seeder** (single-node):

- **Storage: persistent** (ADR-0026) — Harbor state survives a node rebuild. Harbor keeps only its own PVCs (registry blobs 20Gi, jobLog 1Gi, trivy 5Gi); `storageClass` unset → seeder default (`synology-iscsi-storage`).
- **DB + Redis: external** (`type: external`, #84) — Postgres via the `cnpg-postgres` capability (CloudNativePG), Redis via `redis-managed` (Valkey operator). Harbor no longer ships the `harbor-database` / `harbor-redis` StatefulSets.
- **Exposure: clusterIP**, TLS terminated externally at the Cilium Gateway (Gateway-API-only hard constraint, no Ingress).
- **Auth: db_auth** (admin) — OIDC via Dex to follow.
- **Secrets** (ADR-0023, Class B — consumer-supplied):
  - `harbor-runtime-secret` — keys `HARBOR_ADMIN_PASSWORD` + `secretKey` (consumer delivers via SOPS).
  - `harbor-db` — key `password` (Postgres; CNPG auto-creates `<cluster>-app` with this key).
  - `harbor-redis` — key `REDIS_PASSWORD` (Redis; map from the Valkey-operator secret).
  - Internal service secrets (core/xsrf/jobservice/registry-http) are still Harbor-generated.
- **externalURL**: placeholder `https://REPLACE-ME.harbor.invalid` → consumer patches via Kustomize (Class-A structural value).

The concrete CNPG `Cluster` (`harbor-pg` → service `harbor-pg-rw`) and `Valkey` CR (`harbor-cache:6379`) are **consumer-owned** (seeder repo), not part of this render. Customization contract: [`customization.yaml`](customization.yaml).

## Dex / OIDC SSO (Day-2, consumer-owned)

Harbor authenticates against the cluster **Dex** via its native OIDC mode — but
this is **runtime config, not a Helm value**: the goharbor chart exposes no OIDC
knob, so the signed workload here ships **unchanged**. Binding is a **Day-2 step**
the consumer cluster repo performs after Harbor is Ready (API `PUT /configurations`
or UI → Administration → Configuration → Authentication):

| Harbor setting | Value (consumer-supplied) |
|---|---|
| `auth_mode` | `oidc_auth` |
| `oidc_name` | e.g. `dex` |
| `oidc_endpoint` | the cluster Dex issuer URL (ADR-0010) |
| `oidc_client_id` | the static Dex client registered for Harbor |
| `oidc_client_secret` | from the consumer secret `harbor-oidc`, key `OIDC_CLIENT_SECRET` |
| `oidc_scope` | `openid,profile,email,groups,offline_access` |
| `oidc_groups_claim` | `groups` (Dex group claim → Harbor group mapping) |
| `oidc_auto_onboard` | `true` |

The OIDC client secret is **never in the catalog** (base Hard-Constraint). The
consumer creates the `harbor-oidc` secret (SOPS while Vault is offline, later ESO)
and registers a matching **static client in Dex** (clientID + redirect
`https://<harbor-host>/c/oidc/callback`). This is the same per-app Dex-client
model as `lifecycle/crossview` (which ships the hook enabled-on-demand). Dex
itself is a separate prerequisite — see identity/dex (#52), epic #47.

`auth_mode` can only switch DB→OIDC while no non-default local users exist beyond
`admin`; do the binding before onboarding users.

## Sync-wave

`0` — no intra-sub-layer dependency. Cross-sub-layer `requires` (`cnpg-postgres`, `redis-managed`) are ordered by their own sync-waves in the consumer cluster manifests; the CNPG `Cluster` + `Valkey` CR must be Ready before Harbor starts.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/registry/harbor:vX.Y.Z
```

## Consumed by

- **Seeder** — as a pull-through cache in front of GHCR/Docker Hub
- **office-lab** — as a workload registry for internal Devoba apps

Both clusters run Harbor independently (own CNPG `Cluster`, own Valkey instance, own registry-blob PVC).

## Related ADRs

- [ADR-0012 — Platform registry proxy (Harbor on the seeder)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-cluster registry (Harbor on both clusters)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)
- [ADR-0023 — Consumer-side value layering](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0023-value-layering.md)
- [ADR-0026 — Harbor persistent storage](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0026-harbor-persistence.md)
