# Komponente `lifecycle/compositions`

`CompositeResourceDefinition` `XCluster` + zugehörige `Composition` für die Office-Lab-Provisionierung.

`XCluster` ist die plattform-interne API. Ein `XCluster`-Manifest beschreibt einen kompletten Talos-Child-Cluster (`clusterName`, `talosVersion`, `nodes`, `platformBaseTag`, `appsSubLayerPins`). Die Composition rendert daraus eine 3-Step-Pipeline:

1. **`Workspace`** (provider-terraform) — provisioniert die Talos-Maschinen via `talos-cluster`-Modul.
2. **`Release`** (provider-helm) — installiert Cilium ins frische Cluster.
3. **`Release`** (provider-helm) — installiert ArgoCD ins frische Cluster, das danach den Rest der Apps zieht.

## Inhalt

- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition` (Schema: clusterName, talosVersion, nodes, platformBaseTag, appsSubLayerPins).
- `manifests/composition-xcluster.yaml` — `Composition` als 3-Step-Pipeline.

## Sync-Wave-Position

`sync-wave: "20"` — braucht `lifecycle/providers` (Provider-Pods müssen ready sein, sonst landen die `Workspace`/`Release`-Resources im Pending).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/compositions:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
