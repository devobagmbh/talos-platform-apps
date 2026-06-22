# Component `observability/grafana`

[Grafana](https://grafana.com/docs/grafana/latest/) — the platform's **dashboard /
visualisation frontend** (capability `dashboards`,
[ADR-0015](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)).
Grafana renders dashboards and alerts over the observability backends — Loki
(logs), Mimir (metrics), and Tempo (traces) — and authenticates users through Dex
via OIDC.

It implements one capability in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Dashboard / visualisation frontend | `dashboards` | `label-move` |

A consumer MAY substitute another implementation (e.g. Perses) per the index
`swap_class`.

## Contents

A `kind: helm` wrapper over the `grafana` chart plus
`manifests/00-namespace.yaml`:

- A `Deployment` (`grafana`) with the chart's **datasource** and **dashboard**
  discovery sidecars, plus `Service` (ClusterIP), `ServiceAccount`, and the
  `Role`/`RoleBinding` the sidecars need to list/watch ConfigMaps.
- A dedicated `grafana` `Namespace` carrying
  `pod-security.kubernetes.io/enforce: restricted`.

The Grafana image is pinned to the chart appVersion (`13.0.2`); the sidecar /
curl images stay pinned at their chart defaults — never `:latest`.

This component ships **no** CustomResourceDefinitions, so strict-B (ADR-0028) does
not apply and there is no `-crds` companion artifact. The rendered workload
contains zero `kind: CustomResourceDefinition`.

## Chart source — grafana-community migration

The original `grafana/grafana` chart at `https://grafana.github.io/helm-charts` is
now a **frozen stub** (last `10.5.15`, 2026-01-30). Active development moved to the
community-maintained chart:

```
grafana-community/grafana  →  https://grafana-community.github.io/helm-charts
```

This component renders from `grafana-community/grafana` version `12.4.8`
(appVersion `13.0.2`). VERIFY the current chart at publish
(`helm show chart grafana --repo https://grafana-community.github.io/helm-charts --version 12.4.8`).

## Freeze-line (ADR-0024 v2)

The **workload** (the rendered Deployment/Service/SA/RBAC + discovery sidecars) is
catalog-owned and signed; the **config** (datasources, dashboards, OIDC, admin) is
100% consumer-owned across three contract surfaces:

- **Shape (a) — non-secret env.** Grafana reads native config from
  `GF_<SECTION>_<KEY>` environment variables. The consumer's
  `grafana-runtime-config` ConfigMap is injected via `envFromConfigMaps`, carrying
  `GF_SERVER_ROOT_URL` and the `GF_AUTH_GENERIC_OAUTH_*` OIDC endpoint / client-id /
  scope keys.
- **Shape (c) — secret env.** The consumer's `grafana-runtime-secret` Secret is
  injected via `envFromSecrets` (the OIDC client secret) AND wired to the admin
  user/password via `admin.existingSecret`. Setting `admin.existingSecret`
  **suppresses** the chart's literal admin Secret (the chart bakes one only when
  that value is empty), so the catalog ships **no literal admin credential**.
- **Shape (d) — label discovery.** The datasource + dashboard sidecars watch
  ConfigMaps cluster-wide by label (`grafana_datasource=1` / `grafana_dashboard=1`)
  and import them. The catalog ships **no** datasources and **no** dashboards.

The signed workload is never patched.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships
none of these:

- **`grafana-runtime-config` ConfigMap** carrying the non-secret env keys:
  `GF_SERVER_ROOT_URL`, `GF_AUTH_GENERIC_OAUTH_ENABLED`,
  `GF_AUTH_GENERIC_OAUTH_CLIENT_ID`, `GF_AUTH_GENERIC_OAUTH_AUTH_URL`,
  `GF_AUTH_GENERIC_OAUTH_TOKEN_URL`, `GF_AUTH_GENERIC_OAUTH_API_URL`,
  `GF_AUTH_GENERIC_OAUTH_SCOPES`. These point at the cluster's public root URL and
  the Dex OIDC endpoints and live nowhere in the catalog.
- **`grafana-runtime-secret` Secret** carrying the secret keys:
  `GF_SECURITY_ADMIN_USER`, `GF_SECURITY_ADMIN_PASSWORD`, and
  `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` (the Dex static-client secret) — via SOPS
  (seeder) / Vault + ESO (office-lab). The catalog ships no secrets.
- **Labelled datasource / dashboard ConfigMaps** (`grafana_datasource=1` /
  `grafana_dashboard=1`) for the Loki/Mimir/Tempo datasources and any dashboards.
  Datasources, dashboards, and the OIDC values are **per-cluster consumer
  overlay** — they differ per cluster and are never baked into the catalog.
- The **HTTPRoute** fronting Grafana on the Cilium Gateway (TLS terminates there;
  the public root URL is `GF_SERVER_ROOT_URL` + the HTTPRoute host). Base
  Hard-Constraint: no Ingress (`ingress.enabled: false`).
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

## Namespace & Pod Security

The component ships a dedicated `grafana` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule) carrying
`pod-security.kubernetes.io/enforce: restricted` plus `audit`/`warn` at
`restricted`.

`restricted` is **derived from the rendered workload**, not assumed: the pod sets
`runAsNonRoot: true` / `runAsUser: 472` + `seccompProfile: RuntimeDefault`, and
every container (the `grafana` container plus the datasource/dashboard sidecars)
sets `allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]` +
`seccompProfile: RuntimeDefault`. `persistence.enabled: false` suppresses the
chart's root `initChownData` init-container, so no container or init-container runs
as root. Confirmed via `task render:one`.

## Sync-wave

`20` — Grafana fronts the wave-10 storage backends (Loki/Mimir/Tempo) as
datasources and authenticates against Dex, so it deploys after them.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/grafana:X.Y.Z
```

The OCI registry tag at publish is the bare SemVer `X.Y.Z` (`task push` strips the
leading `v`); the corresponding git tag is `observability/grafana-vX.Y.Z` (kept
distinct — registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0010 — Identity provider (dex / OIDC)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md)
