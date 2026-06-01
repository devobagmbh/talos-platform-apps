# Komponente `lifecycle/compositions`

`CompositeResourceDefinition` `XCluster` (Claim-Kind `Cluster`) + zugehörige `Composition` für den deklarativen Cluster-Lifecycle aller Devoba-Talos-Cluster (Seeder + DHQ + zukünftige).

Modell: **ConfigMap-Pattern** ([talos-platform-docs ADR-0022](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0022-xcluster-composition.md)). `cluster.yaml`-Inhalt liegt 1:1 als ConfigMap im Cluster (vom Konsumenten-Repo bereitgestellt). Die Composition zieht sie zur Render-Zeit über `function-extra-resources` und parst sie über `function-go-templating` zu einer `Workspace`-CR für `provider-terraform`.

## Inhalt

- `manifests/xrd-xcluster.yaml` — `CompositeResourceDefinition`. Schema bewusst klein und stabil: `platformBaseTag`, `tofuModuleSource`, `appsSubLayerPins` (optional), `s3StateBackend`. Kein `cluster.yaml`-Schema im XRD.
- `manifests/composition-xcluster.yaml` — `Composition` als 1-Schritt-Lifecycle-Pipeline (`pull-cluster-config` → `render-workspace`).

## Konvention für die `cluster-config`-ConfigMap (Konsumenten-Verantwortung)

Die Composition findet die ConfigMap über einen **Label-Selector**. Konsumenten-Repos müssen folgendes liefern:

| Aspekt | Wert |
|---|---|
| Namespace | `crossplane-system` |
| Label | `platform.devoba.de/cluster: <claim-name>` (matched `spec.claimRef.name`) |
| `data.cluster.yaml` | Vollständiger `cluster.yaml`-Inhalt (1:1 das Schema von `talos-platform-base/cluster.yaml.example`) |

Beispiel:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: seeder-cluster-config
  namespace: crossplane-system
  labels:
    platform.devoba.de/cluster: seeder
data:
  cluster.yaml: |
    cluster:
      name: seeder
      vip: 10.1.12.110
      ntp_servers: [10.1.12.50, time.cloudflare.com]
      # …
    roles: { … }
    nodes: [ … ]
```

## Lifecycle-Walk-Through

1. Konsument editiert `cluster.yaml`-Inhalt im jeweiligen Cluster-Repo, commit + push.
2. Konsument-eigene Argo-Application syncet die ConfigMap in den Seeder-Cluster.
3. Crossplane reconciled den `Cluster`-Claim → Composition → `Workspace` → `provider-terraform` → `tofu apply` läuft.
4. Outputs (kubeconfig, talosconfig) landen im Connection-Secret `<claim-name>-connection` (Namespace `crossplane-system`).
5. ArgoCD ist bereits aus dem Base-Bootstrap im Cluster → zieht die jeweiligen App-of-Apps weiter.

## Sync-Wave-Position

`sync-wave: "20"` — braucht `lifecycle/providers` (Provider-Pods + Composition-Functions müssen ready sein, sonst landen die `Workspace`-Resources im `Pending`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/compositions:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0022 — XCluster-Composition](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0022-xcluster-composition.md) (dieses Design)
- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0003 — Bootstrap-Staging](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0003-bootstrap-staging.md)
- [ADR-0006 — TF-State-Management (Garage-Backend)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
- [ADR-0009 — Multi-Layer-OCI-Distribution](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
