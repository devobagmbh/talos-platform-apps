# Sub-Layer `lifecycle`

Crossplane + Provider + iPXE-Server für Stage-1-Child-Cluster-Provisionierung.

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| Crossplane | Helm `crossplane-stable/crossplane` | Composite-Resource-Engine |
| provider-terraform | Crossplane-Provider-Package | wrappt OpenTofu für Talos-Provisioning |
| provider-helm | Crossplane-Provider-Package | bootstrappt Cilium/Linstor/Argo nach Cluster-Up |
| provider-kubernetes | Crossplane-Provider-Package | post-bootstrap K8s-Manifeste |
| iPXE-Server | OCI-Image + Helm-Chart oder eigenes Manifest | PXE-Boot-Server für DHQ-Nodes (statische Boot-Skripte aus Garage) |
| XClusterDefinition + Composition | dieses Repo | `XCluster`-CRD und passende `Composition` für DHQ-Provisionierung |

## Konsumiert von

- **Seeder** — exklusiv. DHQ-Provisionierung läuft vom Seeder aus.
- **DHQ** — nein (DHQ provisioniert keine weiteren Cluster, vorerst).

## Inhalt

- `helm/crossplane.yaml` — Operator-Werte (Format: `metadata` mit `chart`/`repo`/`version`/`namespace` + `values`-Block, siehe Sub-Layer-Render-Konvention)
- `helm/ipxe.yaml` — iPXE-Server-Stub (`metadata.inline: true` — Custom-Manifeste folgen mit Issue #28 in einem Konsumenten-Repo)
- `manifests/providers.yaml` — `Provider`-CRs für terraform/helm/kubernetes (Versionen gepinnt)
- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition` für `XCluster` (Schema-Felder: clusterName, talosVersion, nodes, platformBaseTag, appsSubLayerPins)
- `manifests/composition-xcluster.yaml` — `Composition` als 3-Step-Pipeline (Tofu-Workspace → Cilium → ArgoCD)
- `compatibility.yaml` — `requires.talos-platform-base` + `provides`-Liste (Crossplane + Provider-Versionen)

## Render-Konvention

Dieser Sub-Layer wird via `task render:one -- lifecycle` zu `rendered/manifest.yaml` gerendert. Die `helm/*.yaml`-Files haben ein zweiteiliges Schema:

```yaml
metadata:
  chart: crossplane                          # Helm-Chart-Name
  repo: https://charts.crossplane.io/stable  # Helm-Repo-URL
  version: 1.18.0                            # gepinnte Version
  namespace: crossplane-system               # Ziel-Namespace
values:
  # ... Helm-Values, werden via helm template --values übergeben
```

Für Custom-Stubs ohne externen Chart: `metadata.inline: true` — der Renderer erzeugt dann ein Namespace-Skelett mit Labels statt eines Helm-Outputs.

## Backlog-Issue

[#12 — Sub-Layer `lifecycle/`: Crossplane + iPXE](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+lifecycle)

Vorgelagert: [#11 — OpenTofu-Modul `talos-cluster` schreiben](https://github.com/devobagmbh/talos-platform-apps/issues/?q=OpenTofu-Modul+talos-cluster) — das Modul wird vom `Workspace` referenziert und liegt im Konsumenten-Repo (`talos-seeder-cluster/stage-1/modules/talos-cluster/`), nicht hier.

## Verwandte ADRs

- [ADR-0003 — Bootstrap-Staging](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0003-bootstrap-staging.md)
- [ADR-0004 — Cluster-Lifecycle-Tooling (Crossplane + provider-terraform)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0005 — Bare-Metal-PXE-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0005-bare-metal-pxe-strategy.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
