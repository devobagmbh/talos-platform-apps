# Component `lifecycle/compositions`

`CompositeResourceDefinition` `XCluster` + its `Composition` for child-cluster provisioning (e.g. office-lab).

`XCluster` is the platform-internal API. **Arch B (DRY):** the claim is **thin** — `clusterName` + `tofuModuleSource` (+ optional `secretName`). It does **not** carry cluster identity (nodes/classes/versions). That identity lives once in the consumer's committed `cluster.yaml`, read by the consumer's self-contained `stage-1/` tofu root — the **same root** the Stage-0 laptop `tofu apply` runs. Update = edit `cluster.yaml` once, never the claim too.

The Composition is **tofu-only**: a single `Workspace` (provider-terraform) runs that consumer root (`source: Remote`, `module` = `tofuModuleSource`). Crossplane passes only **secrets** through (`TF_VAR_sops_age_key`, `TF_VAR_tf_encryption_passphrase`, Garage `AWS_*`) via the per-cluster Secret `<clusterName>-tofu-secrets`, and collects the `kubeconfig`/`talosconfig` outputs; `function-auto-ready` derives the Ready status.

**No** downstream Cilium/ArgoCD Helm step: the child brings its substrate itself — `talos-platform-base` v0.7.0 delivers ArgoCD via `deploy_argocd` (PR #102) and Cilium via Recipe as a Talos `inlineManifest` at bootstrap. The base health gate (`data.talos_cluster_health`) waits for nodes=Ready (CNI up) before `tofu apply` returns. Once the child is up, its own (inlineManifest) ArgoCD takes over GitOps from the child repo.

## Contents

- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition` (**thin**: clusterName, tofuModuleSource, optional secretName).
- `manifests/composition-xcluster.yaml` — `Composition` (`mode: Pipeline`, runs the consumer root → ready). Contains `VERIFY` markers for the provider-terraform `Workspace` env/backend shape to confirm against a running Crossplane.

> **ADR-0022 note:** Arch B (thin claim + consumer-root-runner) follows the base OpenTofu cutover (v0.7.0, node/class defs in the consumer root) + PR #102 (ArgoCD via tofu). ADR-0022 (old ConfigMap+go-templating pattern) needs a matching revision — tracked in talos-platform-docs#72.

## Sync-wave position

`sync-wave: "20"` — requires `lifecycle/providers` (provider + function pods must be ready, otherwise the `Workspace` resources stay Pending).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/compositions:vX.Y.Z
```

## Related ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
