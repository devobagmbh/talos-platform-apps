# Component `lifecycle/crossview`

[Crossview](https://github.com/crossplane-contrib/crossview) (crossplane-contrib) —
a web dashboard that **visualizes and inspects Crossplane resources** (XRs, Compositions,
managed resources, provider state). Read-only by default; useful on the seeder, which is
the cluster that runs the Crossplane control plane (ADR-0004 / ADR-0022).

Helm chart `crossview` from `https://crossplane-contrib.github.io/crossview`, pinned to
**4.4.0**. Ships a read-only `ClusterRole` + ServiceAccount so it can read Crossplane
resources cluster-wide, an embedded Postgres for its own state, and optional OIDC/SAML SSO.

## Freeze-line (ADR-0024)

The **workload** (Deployment/Service/RBAC + embedded DB) is the signed, pre-rendered
artifact. **Consumer-owned** (Layer 3):

- **Secrets (Shape c)** — `adminPassword`, `dbPassword`, `sessionSecret` (+ `OIDCClientSecret`
  when SSO is on), via an existing Secret `crossview-runtime-secret`. The catalog ships only
  placeholders; never a real credential (base Hard-Constraint).
- **Config (Shape b)** — the public host / CORS origin and, when enabled, the Dex OIDC wiring
  (issuer/clientId/callbackURL, ADR-0010). SSO is off in the catalog default.

The DB backend (embedded Postgres vs external CNPG) is a **Workload-Variant-Axis** (ADR-0024),
not a config dimension.

## Sync-wave

`30` — after `lifecycle/crossplane` (0) + `providers` (10) + `compositions` (20): crossview
reads the Crossplane CRs, so the CRDs + control plane must exist first.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/crossview:vX.Y.Z
```

## Consumed by

- **Seeder** — yes (the Crossplane control-plane cluster; the dashboard belongs where the XRs live).
- **office-lab** — optional (office-lab does not run Crossplane in phase 1).

## Related ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0022 — XCluster-Composition](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0022-xcluster-composition.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0010 — Identity-Provider (Dex OIDC for SSO)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)
