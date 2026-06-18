# Component `lifecycle/crossview`

[Crossview](https://github.com/crossplane-contrib/crossview) (crossplane-contrib) —
a web dashboard that **visualizes and inspects Crossplane resources** (XRs, Compositions,
managed resources, provider state). Read-only by default; useful on a consumer that runs
the Crossplane control plane (ADR-0004 / ADR-0022).

Helm chart `crossview` from `https://crossplane-contrib.github.io/crossview`, pinned to
**4.4.0**. Ships a read-only `ClusterRole` + ServiceAccount so it can read Crossplane
resources cluster-wide, plus optional OIDC/SAML SSO. Its state DB is **external** —
Postgres comes from the `cnpg-postgres` capability (#85), not a bundled Postgres.

## Freeze-line (ADR-0024)

The **workload** (Deployment/Service/RBAC) is the signed, pre-rendered artifact.
Postgres is external (consumer-owned CNPG `Cluster`). **Consumer-owned** (Layer 3):

- **Secrets (Shape c)** — `adminPassword` + `sessionSecret` (+ `OIDCClientSecret` when SSO
  is on) via an existing Secret `crossview-runtime-secret`; the DB password via a second
  Secret `crossview-db` key `password` (point it at CNPG's auto-created `<cluster>-app`
  secret). The catalog ships only placeholders; never a real credential (base Hard-Constraint).
- **Config (Shape b)** — the public host / CORS origin and, when enabled, the Dex OIDC wiring
  (issuer/clientId/callbackURL, ADR-0010). SSO is off in the catalog default.

## External Postgres (cnpg-postgres)

`database.enabled=false` drops the chart's bundled Postgres; `config.database` points the
app at the consumer CNPG service `crossview-pg-rw:5432` (db `crossview`, user `crossview`,
`sslmode=require`). The concrete CNPG `Cluster` (`crossview-pg`) + the `crossview-db` secret
are wired in the consumer repo. See [`compatibility.yaml`](compatibility.yaml)
`requires: cnpg-postgres`.

## Sync-wave

`30` — after `lifecycle/crossplane` (0) + `providers` (10) + `compositions` (20): crossview
reads the Crossplane CRs, so the CRDs + control plane must exist first.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/crossview:vX.Y.Z
```

## Consumed by

- A Crossplane control-plane consumer — yes (the dashboard belongs where the XRs live).
- A consumer not running Crossplane — optional (no Crossplane control plane in phase 1).

## Related ADRs

- ADR-0004 — Cluster-Lifecycle-Tooling
- ADR-0022 — XCluster-Composition
- ADR-0024 — Workload/Config-Freeze-Line
- ADR-0010 — Identity-Provider (Dex OIDC for SSO)
