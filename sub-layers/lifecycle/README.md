# Sub-Layer `lifecycle`

Crossplane + Provider + iPXE-Server für Stage-1-Child-Cluster-Provisionierung.

Der Sub-Layer ist eine organisatorische Klammer; **OCI-Distribution erfolgt pro Komponente** (ADR-0009). Jede Komponente hat ein eigenes Helm-Chart-Wrapper-OCI, eine eigene Argo-Application und einen eigenen Lifecycle.

## Komponenten

| Komponente | sync-wave | Inhalt | OCI |
|---|---|---|---|
| [`crossplane`](components/crossplane/) | 0 | Crossplane-Operator (Helm) — bringt CRDs | `oci://.../lifecycle/crossplane:vX.Y.Z` |
| [`ipxe`](components/ipxe/) | 0 | iPXE-Server-Stub (Namespace + Labels, Inhalt in Issue #28) | `oci://.../lifecycle/ipxe:vX.Y.Z` |
| [`providers`](components/providers/) | 10 | provider-opentofu + Pipeline functions | `oci://.../lifecycle/providers:vX.Y.Z` |
| [`compositions`](components/compositions/) | 20 | `XCluster`-XRD + Composition (3-Step-Pipeline) | `oci://.../lifecycle/compositions:vX.Y.Z` |

Sync-Wave folgt der CRD-Bootstrap-Reihenfolge: Wave 0 erzeugt die Crossplane-CRDs, Wave 10 die Provider-CRs (brauchen `pkg.crossplane.io/Provider`), Wave 20 die XRD+Composition (brauchen aktive Provider).

## Konsumiert von

- **Seeder** — exklusiv. Office-Lab-Provisionierung läuft vom Seeder aus.
- **Office-Lab** — nein (Office-Lab provisioniert keine weiteren Cluster, vorerst).

## Render-Konvention

Jede Komponente wird via `task render:one -- lifecycle/<component>` zu `components/<component>/rendered/manifest.yaml` gerendert. Dann pro Komponente packaged + gepusht:

```bash
task render:one -- lifecycle/crossplane
task package    -- lifecycle/crossplane 0.1.0
task push       -- lifecycle/crossplane 0.1.0
# oder zusammen:
task publish    -- lifecycle/crossplane v0.1.0
```

Sub-Layer-Level-Aggregat: `task render -- lifecycle` rendered alle Komponenten dieses Sub-Layers.

Eingabe-Konvention pro Komponente:

| Verzeichnis | Inhalt |
|---|---|
| `helm/*.yaml` | YAML mit `metadata.{chart,repo,version,namespace}` + `values` — oder `metadata.inline: true` für Custom-Stubs |
| `manifests/*.yaml` | Raw-Manifeste, werden 1:1 konkateniert |

## Backlog-Issue

[#12 — Sub-Layer `lifecycle/`: Crossplane + iPXE](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+lifecycle)

Vorgelagert: [#11 — OpenTofu-Modul `talos-cluster` schreiben](https://github.com/devobagmbh/talos-platform-apps/issues/?q=OpenTofu-Modul+talos-cluster) — das Modul wird vom `Workspace` referenziert und liegt im Konsumenten-Repo (`talos-seeder-cluster/stage-1/modules/talos-cluster/`), nicht hier.

## Verwandte ADRs

- [ADR-0003 — Bootstrap-Staging](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0003-bootstrap-staging.md)
- [ADR-0004 — Cluster-Lifecycle-Tooling (Crossplane + provider-terraform)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0005 — Bare-Metal-PXE-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0005-bare-metal-pxe-strategy.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) (Komponenten-OCI-Granularität)
