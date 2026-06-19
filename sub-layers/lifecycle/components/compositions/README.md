# Component `lifecycle/compositions`

`CompositeResourceDefinition` `XCluster` + its `Composition` for child-cluster provisioning.

`XCluster` is the platform-internal API. **Crossplane v2:** the XRD is `apiextensions.crossplane.io/v2`, `scope: Namespaced` — the consumer creates a namespaced `XCluster` directly (no v1 claim). **Arch B (DRY):** that `XCluster` is **thin** — `clusterName` + `tofuModuleSource`. It does **not** carry cluster identity (nodes/classes/versions). That identity lives once in the consumer's committed `cluster.yaml`, read by the consumer's self-contained `stage-1/` tofu root — the **same root** the Stage-0 laptop `tofu apply` runs. Update = edit `cluster.yaml` once, never the `XCluster` too.

The Composition is **tofu-only**: a single `Workspace` (provider-**opentofu**, namespaced `opentofu.m.upbound.io/v1beta1`) runs that consumer root (`source: Remote`, `module` = `tofuModuleSource`). provider-opentofu, not -terraform, because the roots use OpenTofu 1.7+ state encryption that the Terraform-1.5.7-frozen provider cannot run. Crossplane passes only **secrets** through (`TF_VAR_sops_age_key`, `TF_VAR_tf_encryption_passphrase`, Garage `AWS_*`) via the per-cluster Secret `<clusterName>-tofu-secrets`; the `Workspace` writes the `kubeconfig`/`talosconfig` outputs to its own connection secret `<clusterName>-cluster-conn` (Crossplane v2 dropped native XR connection-detail aggregation), and `function-auto-ready` derives the Ready status.

**No** downstream Cilium/ArgoCD Helm step: the child brings its substrate itself — `talos-platform-base` v0.8.0 delivers ArgoCD via `deploy_argocd` (PR #102) and Cilium via Recipe as a Talos `inlineManifest` at bootstrap. The base health gate (`data.talos_cluster_health`) waits for nodes=Ready (CNI up) before `tofu apply` returns. Once the child is up, its own (inlineManifest) ArgoCD takes over GitOps from the child repo.

## Tofu state-seed step (OpenTofu #2518 workaround)

A **brand-new** cluster starts with an **empty** S3 backend. provider-opentofu's `Observe` runs `tofu state list`, which errors `no state` on an empty backend ([OpenTofu #2518](https://github.com/opentofu/opentofu/issues/2518)) — so the `Workspace` never leaves `Observe` and never reaches `apply`. The cluster never bootstraps.

The Composition therefore has a **second pipeline step of three** (step 2 of 3: `Workspace` → `seed-tofu-state` → `ready`; `seed-tofu-state` sits between the `Workspace` step and `ready`) that emits a one-shot `Job` — via a provider-kubernetes namespaced `Object` (`kubernetes.m.crossplane.io/v1alpha1`) — into the `XCluster`'s own namespace. The `Job`:

1. reads THIS cluster's S3 backend config at runtime from the opentofu `ClusterProviderConfig`'s `backendFile` (an init container; keeps this artifact cluster-agnostic — it bakes in no bucket/key),
2. runs `tofu init` against that backend with a minimal root carrying ONLY the `backend "s3" {}` + the state-`encryption {}` block,
3. **seeds an empty state if and only if the backend is definitively empty.**

The step needs **no hard ordering** with the `Workspace`: the `Workspace` keeps erroring in `Observe` until the seed lands, then its backoff retry succeeds and it proceeds to `apply`.

### Idempotency & never-overwrite guarantee (BCP-14)

The `Job` is **seed-if-empty** and MUST be safe to re-run / re-create. Two independent guards protect existing state:

- **Guard 1 — conservative emptiness check.** The script pushes an empty state ONLY when `tofu state pull` returns empty/whitespace-only output (the #2518 empty-backend signal). On ANY state body (even serial 0 with no resources) it is a **no-op (exit 0)**. On ANY error or ambiguity (auth, network, decryption) it **does NOT push and exits non-zero so the `Job` retries** — it never pushes on uncertainty.
- **Guard 2 — `tofu state push` without `-force`.** OpenTofu's own serial/lineage check is a second barrier; it refuses to overwrite a higher-serial remote state that appeared between the pull and the push.

Re-running on an already-seeded or in-use backend is therefore a no-op. The pushed state is a minimal valid v4 state (serial 0, empty resources/outputs).

**DR note (state restore is safe).** Restoring an existing tofu state into the S3 backend — whether before or after `XCluster` creation — is safe: the seed guard treats ANY non-empty `tofu state pull` as existing state and never overwrites it (no-op, exit 0). A restored backup is therefore preserved by the seed step, never clobbered.

> **Encryption-block lockstep (reviewer-confirmed).** The `Job`'s embedded `encryption {}` (pbkdf2 key provider → aes_gcm method) MUST match the consumer stage-1 root's `encryption {}` **byte-for-byte**, or the pushed empty state is unreadable by the real `apply`. Keep the two in lockstep when either changes.

## Contents

- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition` (`apiextensions.crossplane.io/v2`, `scope: Namespaced`; **thin**: clusterName, tofuModuleSource).
- `manifests/composition-xcluster.yaml` — `Composition` (`mode: Pipeline`: `Workspace` → `seed-tofu-state` → `ready`). One `VERIFY` marker remains: the base module output names surfaced into the `Workspace` connection secret (`kubeconfig`/`talosconfig`), to confirm at first reconcile.

## Consumer obligations (Layer 3 — MUST)

This catalog component is the cluster-agnostic template; the consumer cluster repo MUST supply, in the `XCluster`'s namespace unless noted:

1. **Per-cluster runner Secret `<clusterName>-tofu-secrets`** (SOPS/ESO) with keys `sops_age_key`, `tf_encryption_passphrase`, `aws_access_key_id`, `aws_secret_access_key`. Used by BOTH the `Workspace` and the seed `Job`. The catalog never ships a real credential.
2. **opentofu `ClusterProviderConfig`** (cluster-scoped, name = the `XCluster`'s `providerConfigName`, default `opentofu-default`) whose `backendFile` pins THIS cluster's tofu state (Garage bucket/key). MUST be unique per cluster.
3. **kubernetes `ClusterProviderConfig` named `kubernetes-default`** (cluster-scoped, `InjectedIdentity`). Shared across all `XCluster`s — it carries no per-cluster state. The seed `Object` references it by this fixed name.
4. **Seed-`Job` ServiceAccount `<clusterName>-tofu-state-seed` + its RBAC**: a `ClusterRole` granting `get` on `clusterproviderconfigs.opentofu.m.upbound.io` (cluster-scoped) and a `ClusterRoleBinding` to that SA. The Composition deliberately does NOT emit the SA/Role/Binding — emitting RBAC would require provider-kubernetes to hold RBAC-creation rights (privilege escalation). RBAC is consumer infrastructure, not freeze-line config.

   Minimal least-privilege RBAC to copy-paste (replace `<clusterName>`/`<namespace>`):

   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: <clusterName>-tofu-state-seed
   rules:
     - apiGroups: ["opentofu.m.upbound.io"]
       resources: ["clusterproviderconfigs"]
       verbs: ["get"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: <clusterName>-tofu-state-seed
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: <clusterName>-tofu-state-seed
   subjects:
     - kind: ServiceAccount
       name: <clusterName>-tofu-state-seed
       namespace: <namespace>
   ```

**Prerequisite (`lifecycle/providers`).** The seed step uses the namespaced provider-kubernetes `Object` API (`kubernetes.m.crossplane.io/v1alpha1`). `lifecycle/providers` MUST install `provider-kubernetes` for this to reconcile — see [`compatibility.yaml`](compatibility.yaml) `requires: lifecycle/providers`.

> **ADR-0022 note:** Arch B (thin claim + consumer-root-runner) follows the base OpenTofu cutover (v0.7.0, node/class defs in the consumer root) + PR #102 (ArgoCD via tofu). ADR-0022 (old ConfigMap+go-templating pattern) needs a matching revision — tracked in talos-platform-docs#72.

## Sync-wave position

`sync-wave: "20"` — requires `lifecycle/providers` (provider + function pods must be ready, otherwise the `Workspace` resources stay Pending).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/compositions:vX.Y.Z
```

## Related ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
