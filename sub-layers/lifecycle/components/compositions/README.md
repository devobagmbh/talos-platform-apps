# Component `lifecycle/compositions`

`CompositeResourceDefinition` `XCluster` + its `Composition` for child-cluster provisioning.

`XCluster` is the platform-internal API. **Crossplane v2:** the XRD is `apiextensions.crossplane.io/v2`, `scope: Namespaced` — the consumer creates a namespaced `XCluster` directly (no v1 claim). **Arch B (DRY):** that `XCluster` is **thin** — `clusterName` + `tofuModuleSource`. It does **not** carry cluster identity (nodes/classes/versions). That identity lives once in the consumer's committed `cluster.yaml`, read by the consumer's self-contained `stage-1/` tofu root — the **same root** the Stage-0 laptop `tofu apply` runs. Update = edit `cluster.yaml` once, never the `XCluster` too.

The Composition is **tofu-only**: a single `Workspace` (provider-**opentofu**, namespaced `opentofu.m.upbound.io/v1beta1`) runs that consumer root (`source: Remote`, `module` = `tofuModuleSource`). provider-opentofu, not -terraform, because the roots use OpenTofu 1.7+ state encryption that the Terraform-1.5.7-frozen provider cannot run. Crossplane passes only **secrets** through (`TF_VAR_sops_age_key`, `TF_VAR_tf_encryption_passphrase`, Garage `AWS_*`) via the per-cluster Secret `<clusterName>-tofu-secrets`; the `Workspace` writes the `kubeconfig`/`talosconfig` outputs to its own connection secret `<clusterName>-cluster-conn` (Crossplane v2 dropped native XR connection-detail aggregation), and `function-auto-ready` derives the Ready status.

**No** downstream Cilium/ArgoCD Helm step: the child brings its substrate itself — `talos-platform-base` v0.8.0 delivers ArgoCD via `deploy_argocd` (PR #102) and Cilium via Recipe as a Talos `inlineManifest` at bootstrap. The base health gate (`data.talos_cluster_health`) waits for nodes=Ready (CNI up) before `tofu apply` returns. Once the child is up, its own (inlineManifest) ArgoCD takes over GitOps from the child repo.

## Contents

- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition` (`apiextensions.crossplane.io/v2`, `scope: Namespaced`; **thin**: clusterName, tofuModuleSource).
- `manifests/composition-xcluster.yaml` — `Composition` (`mode: Pipeline`, runs the consumer root → ready). One `VERIFY` marker remains: the base module output names surfaced into the `Workspace` connection secret (`kubeconfig`/`talosconfig`), to confirm at first reconcile.

> **ADR-0022 note:** Arch B (thin claim + consumer-root-runner) follows the base OpenTofu cutover (v0.7.0, node/class defs in the consumer root) + PR #102 (ArgoCD via tofu). ADR-0022 (old ConfigMap+go-templating pattern) needs a matching revision — tracked in talos-platform-docs#72.

## Sync-wave position

`sync-wave: "20"` — requires `lifecycle/providers` (provider + function pods must be ready, otherwise the `Workspace` resources stay Pending).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/compositions:vX.Y.Z
```

## Related ADRs

- ADR-0004 — Cluster-Lifecycle-Tooling
