# Component `lifecycle/ipxe`

HTTP server for static iPXE boot assets. Referenced as the next-boot URL by the DHCP boot path of the consumer-cluster nodes, serving the Talos initial boot config (kernel cmdline → `machine-config` URL).

## Architecture

```
Consumer node (PXE boot)
   │
   │ 1. DHCP: returns 'next-server' + 'filename'
   ▼
ipxe.efi (bootloader, referenced in the DHCP response)
   │
   │ 2. HTTP GET http://<ipxe-svc>:8080/boot.ipxe
   ▼
nginx (this pod)
   │
   │ 3. serves the iPXE script from ConfigMap 'ipxe-boot-scripts'
   ▼
ipxe.efi runs the script
   │
   │ 4. loads Talos kernel + initrd + machine-config URL
   ▼
Talos boots
```

The iPXE server itself runs as a minimal nginx in the cluster and serves only static files from the `ipxe-boot-scripts` ConfigMap. No templating engine, no API calls — keeping it trivially reviewable and auditable.

## Contents

| Resource | Function |
|---|---|
| `Namespace ipxe` | Component boundary, labels for sub-layer selection |
| `ServiceAccount ipxe` | Identity for the Deployment (no RBAC needed — static files only) |
| `ConfigMap ipxe-boot-scripts` | Default skeleton with a placeholder `boot.ipxe`. Overridden with the real boot scripts in the consumer repo (`<consumer-repo>`) |
| `ConfigMap ipxe-nginx` | nginx site config: listen 8080, `Content-Type: text/plain` for `.ipxe` files |
| `Deployment ipxe` | nginx 1.27-alpine, non-root (UID 101), readOnlyRootFilesystem, all capabilities dropped |
| `Service ipxe` | LoadBalancer on port 8080, `io.cilium/lb-ipam-pool: seeder` |

## Cluster-specific configuration

Only the default skeleton lives in `talos-platform-apps`. The consumer repo (`<consumer-repo>`, layer 3) provides:

- **The real `ipxe-boot-scripts` ConfigMap** with the `.ipxe` files (Talos image URL, kernel args, `machine-config` URL per hardware variant).
- **A `CiliumLoadBalancerIPPool` named `seeder`** with the VIP range from which the LB-IPAM annotation gets a concrete IP.
- **DHCP config** on the gateway that propagates this VIP as `next-server`.

## Sync-wave position

`sync-wave: "0"` — independent of Crossplane/providers/compositions. Can run in parallel with `lifecycle/crossplane`.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/ipxe:vX.Y.Z
```

## Related ADRs

- [ADR-0005 — Bare-Metal-PXE-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0005-bare-metal-pxe-strategy.md)
