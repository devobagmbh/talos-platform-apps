# Komponente `lifecycle/ipxe`

HTTP-Server für statische iPXE-Boot-Assets. Wird vom DHCP-Boot-Pfad der Konsumenten-Cluster-Nodes als Next-Boot-URL referenziert und liefert die Talos-Initial-Boot-Konfig (Kernel-Cmdline → `machine-config`-URL).

## Architektur

```
Konsumenten-Node (PXE-Boot)
   │
   │ 1. DHCP: gibt 'next-server' + 'filename' zurück
   ▼
ipxe.efi (Bootloader, im DHCP-Response referenziert)
   │
   │ 2. HTTP GET http://<ipxe-svc>:8080/boot.ipxe
   ▼
nginx (dieser Pod)
   │
   │ 3. liefert iPXE-Skript aus ConfigMap 'ipxe-boot-scripts'
   ▼
ipxe.efi führt das Skript aus
   │
   │ 4. lädt Talos-Kernel + initrd + machine-config-URL
   ▼
Talos bootet
```

Der iPXE-Server selbst läuft als minimaler nginx im Cluster und serviert ausschließlich statische Files aus der `ipxe-boot-scripts`-ConfigMap. Keine Templating-Engine, keine API-Aufrufe — das hält ihn trivial review- und auditbar.

## Inhalt

| Resource | Funktion |
|---|---|
| `Namespace ipxe` | Komponenten-Boundary, Labels für Sub-Layer-Selektion |
| `ServiceAccount ipxe` | Identity für das Deployment (kein RBAC nötig — nur statische Files) |
| `ConfigMap ipxe-boot-scripts` | Default-Skelett mit Platzhalter-`boot.ipxe`. Wird im Konsumenten-Repo (`<consumer-repo>`) mit den echten Boot-Skripten überschrieben |
| `ConfigMap ipxe-nginx` | nginx-Site-Config: Listen 8080, `Content-Type: text/plain` für `.ipxe`-Files |
| `Deployment ipxe` | nginx 1.27-alpine, non-root (UID 101), readOnlyRootFilesystem, alle Capabilities dropped |
| `Service ipxe` | LoadBalancer auf Port 8080, `io.cilium/lb-ipam-pool: seeder` |

## Cluster-spezifische Konfiguration

Im `talos-platform-apps` lebt nur das Default-Skelett. Das Konsumenten-Repo (`<consumer-repo>`, Layer 3) liefert:

- **Echte `ipxe-boot-scripts`-ConfigMap** mit den `.ipxe`-Files (Talos-Image-URL, Kernel-Args, `machine-config`-URL pro Hardware-Variante).
- **`CiliumLoadBalancerIPPool` namens `seeder`** mit der VIP-Range, aus der die LB-IPAM-Annotation eine konkrete IP bekommt.
- **DHCP-Konfig** in der UCG-Max die diese VIP als `next-server` propagiert.

## Sync-Wave-Position

`sync-wave: "0"` — unabhängig von Crossplane/Providern/Compositions. Kann parallel zu `lifecycle/crossplane` laufen.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/ipxe:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0005 — Bare-Metal-PXE-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0005-bare-metal-pxe-strategy.md)
