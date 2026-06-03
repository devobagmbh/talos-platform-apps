# Component `lifecycle/compositions`

`CompositeResourceDefinition` `XCluster` + its `Composition` for child-cluster provisioning (e.g. office-lab).

`XCluster` is the platform-internal API. An `XCluster` manifest describes a complete Talos child cluster (`clusterName`, `clusterEndpoint`, `talosVersion`, `kubernetesVersion`, `nodes` incl. `class`, `classes`, `tofuModuleSource`) — the spec schema mirrors 1:1 the variable contract of the base `talos-cluster` module (v0.7.0).

The Composition is **tofu-only** (changed 2026-06-03): a single `Workspace` (provider-terraform) against the base module; the spec fields are mapped onto the Workspace `varmap` (tfvars) via `function-patch-and-transform`, and `function-auto-ready` derives the Ready status.

**No** downstream Cilium/ArgoCD Helm step anymore: the child brings its substrate itself — `talos-platform-base` v0.7.0 delivers ArgoCD via `deploy_argocd` (PR #102) and Cilium via Recipe as a Talos `inlineManifest` at bootstrap. The base health gate (`data.talos_cluster_health`) already waits for nodes=Ready (CNI up) before `tofu apply` returns — a separate Helm step would be redundant and race the gate. Once the child is up, its own (inlineManifest) ArgoCD takes over GitOps reconciliation from the child repo.

## Contents

- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition` (schema = base variable contract: clusterName, clusterEndpoint, talos/kubernetesVersion, nodes+class, classes, tofuModuleSource, …).
- `manifests/composition-xcluster.yaml` — `Composition` (`mode: Pipeline`, tofu-only: provision → ready).

> **ADR-0022 note:** the tofu-only rework follows the base OpenTofu cutover (v0.7.0, node/class defs in the consumer root) + PR #102 (ArgoCD via tofu). ADR-0022 (ConfigMap pattern) needs a matching revision — tracked separately.

## Sync-wave position

`sync-wave: "20"` — requires `lifecycle/providers` (provider + function pods must be ready, otherwise the `Workspace` resources stay Pending).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/compositions:vX.Y.Z
```

## Related ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
