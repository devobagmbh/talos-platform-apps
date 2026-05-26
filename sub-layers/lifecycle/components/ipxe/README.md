# Komponente `lifecycle/ipxe`

iPXE-Server-Stub für PXE-Boot der DHQ-Nodes. Erzeugt aktuell nur das Namespace-Skelett — die Boot-Skripte (statische TFTP-Files aus Garage) folgen mit Issue #28 in einem Konsumenten-Repo.

## Inhalt

- `helm/ipxe.yaml` — `metadata.inline: true` → der Renderer erzeugt ein Namespace `ipxe` mit Sub-Layer-Labels statt eines Helm-Outputs.

## Sync-Wave-Position

`sync-wave: "0"` — unabhängig von Crossplane/Providern/Compositions. Kann parallel zu `lifecycle/crossplane` laufen.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/ipxe:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0005 — Bare-Metal-PXE-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0005-bare-metal-pxe-strategy.md)
