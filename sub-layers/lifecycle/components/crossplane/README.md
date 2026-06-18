# Komponente `lifecycle/crossplane`

Crossplane-Operator als Composite-Resource-Engine.

Erzeugt die `pkg.crossplane.io`- und `apiextensions.crossplane.io`-CRDs, die alle anderen Komponenten des `lifecycle`-Sub-Layers (Provider-CRs, XRDs, Compositions) als Voraussetzung haben.

## Inhalt

- `helm/crossplane.yaml` — Helm-Chart-Reference (`crossplane-stable/crossplane@1.18.0`, namespace `crossplane-system`) + Default-Values.

## Sync-Wave-Position

Erste Komponente im Sub-Layer (`sync-wave: "0"`). Erzeugt die CRDs, ohne die `providers`, `compositions` und alles weitere im Cluster nicht installierbar wären.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/crossplane:vX.Y.Z
```

## Verwandte ADRs

- ADR-0004 — Cluster-Lifecycle-Tooling
