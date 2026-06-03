# Component `lifecycle/providers`

Crossplane provider **and function** packages for child-cluster provisioning (e.g. office-lab).

| Package | Kind | Version | Purpose |
|---|---|---|---|
| `provider-opentofu` | Provider | v1.1.3 | runs the consumer's `tofu` root for Talos provisioning (the only provider used by the xcluster Composition). **opentofu**, not terraform: the roots use OpenTofu 1.7+ state encryption that the Terraform-1.5.7-frozen `provider-terraform` cannot run. Ships the namespaced `opentofu.m.upbound.io` API for Crossplane v2. |
| `provider-kubernetes` | Provider | v1.2.1 | optional/post-bootstrap K8s manifests into the child (if not delivered via base inlineManifest) |
| `function-patch-and-transform` | Function | v0.10.6 | **mandatory** for Pipeline mode: maps the thin XCluster spec → Workspace fields |
| `function-auto-ready` | Function | v0.6.5 | **mandatory**: derives XCluster Ready from the Workspace |

> Versions verified 2026-06 against the GitHub releases / Upbound marketplace. Target is **Crossplane v2.x** (chart `2.3.1`, greenfield); provider-opentofu v1.1.3 ships the namespaced `opentofu.m.upbound.io` API for v2, the crossplane-contrib functions/provider run on v2.

`provider-helm` was **removed**: Cilium/ArgoCD no longer arrive as a downstream `helm.crossplane.io/Release`, but as a Talos `inlineManifest` at child bootstrap (base v0.8.0 `deploy_argocd` + Cilium recipe). The xcluster Composition is therefore a pure tofu Workspace.

## Contents

- `manifests/providers.yaml` — two `Provider` CRs + two `Function` CRs, versions pinned.

## Sync-wave position

`sync-wave: "10"` — requires `lifecycle/crossplane` (CRD `pkg.crossplane.io/Provider`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/providers:vX.Y.Z
```

## Related ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
