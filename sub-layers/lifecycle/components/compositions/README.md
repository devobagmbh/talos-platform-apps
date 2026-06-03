# Komponente `lifecycle/compositions`

`CompositeResourceDefinition` `XCluster` + zugehörige `Composition` für die Child-Cluster-Provisionierung (z. B. office-lab).

`XCluster` ist die plattform-interne API. Ein `XCluster`-Manifest beschreibt einen kompletten Talos-Child-Cluster (`clusterName`, `clusterEndpoint`, `talosVersion`, `kubernetesVersion`, `nodes` inkl. `class`, `classes`, `tofuModuleSource`) — das spec-Schema spiegelt 1:1 den Variablen-Contract des base-`talos-cluster`-Moduls (v0.7.0).

Die Composition ist **tofu-only** (geändert 2026-06-03): ein einziger `Workspace` (provider-terraform) gegen das base-Modul; die spec-Felder werden via `function-patch-and-transform` auf die Workspace-`varmap` (tfvars) gemappt, `function-auto-ready` leitet den Ready-Status ab.

**Kein** nachgelagerter Cilium-/ArgoCD-Helm-Schritt mehr: Das Child bringt sein Substrat selbst mit — `talos-platform-base` v0.7.0 liefert ArgoCD via `deploy_argocd` (PR #102) und Cilium via Recipe als Talos-`inlineManifest` beim Bootstrap. Der base-Health-Gate (`data.talos_cluster_health`) wartet ohnehin auf Nodes=Ready (CNI da), bevor `tofu apply` zurückkehrt — ein separater Helm-Schritt wäre redundant und liefe gegen den Gate. Sobald das Child oben ist, übernimmt dessen eigene (inlineManifest-)ArgoCD die GitOps-Reconciliation aus dem Child-Repo.

## Inhalt

- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition` (Schema = base-Variablen-Contract: clusterName, clusterEndpoint, talos/kubernetesVersion, nodes+class, classes, tofuModuleSource, …).
- `manifests/composition-xcluster.yaml` — `Composition` (`mode: Pipeline`, tofu-only: provision → ready).

> **ADR-0022-Hinweis:** Umbau auf tofu-only folgt dem base-OpenTofu-Cutover (v0.7.0, node/class-Defs im Konsumenten-Root) + PR #102 (ArgoCD via tofu). ADR-0022 (ConfigMap-Pattern) braucht eine passende Revision — getrennt nachzuziehen.

## Sync-Wave-Position

`sync-wave: "20"` — braucht `lifecycle/providers` (Provider- + Function-Pods müssen ready sein, sonst landen die `Workspace`-Resources im Pending).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/compositions:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
