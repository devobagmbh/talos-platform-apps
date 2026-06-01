# Komponente `lifecycle/providers`

Crossplane-Provider-Pakete + Composition-Functions für die Stage-1-Lifecycle-Pipeline.

| Art | Name | Version | Zweck |
|---|---|---|---|
| Provider | `provider-terraform` | v0.20.0 | wrappt OpenTofu für Talos-Cluster-Provisioning |
| Provider | `provider-helm` | v0.20.0 | ad-hoc Helm-Releases (nicht in XCluster-Pipeline) |
| Provider | `provider-kubernetes` | v0.18.0 | generic K8s-Object-Apply, Connection-Secret-driven |
| Function | `function-extra-resources` | v0.0.6 | lädt referenzierte ConfigMaps zur Render-Zeit (Function-Pipeline-Modus) |
| Function | `function-go-templating` | v0.10.0 | rendert Workspace-CR aus dem `cluster.yaml`-Inhalt der ConfigMap |

Die XCluster-Composition ([`compositions`](../compositions/)) nutzt `function-extra-resources` + `function-go-templating` + `provider-terraform`. `provider-helm` und `provider-kubernetes` sind für Konsumenten-Use-Cases verfügbar (außerhalb der Cluster-Lifecycle-Pipeline).

## Inhalt

- `manifests/providers.yaml` — drei `Provider`- + zwei `Function`-CRs, Versionen gepinnt.

## Sync-Wave-Position

`sync-wave: "10"` — braucht `lifecycle/crossplane` (CRDs `pkg.crossplane.io/Provider` + `pkg.crossplane.io/Function`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/providers:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0022 — XCluster-Composition](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0022-xcluster-composition.md) (Function-Nutzung)
- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
