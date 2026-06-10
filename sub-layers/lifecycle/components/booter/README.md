# Component `lifecycle/booter`

proxyDHCP / PXE responder for the bare-metal boot path, based on
[`siderolabs/booter`](https://github.com/siderolabs/booter) in **standalone mode**
(non-Omni). booter answers PXE/DHCP discovery on the lab boot VLAN and chainloads
the iPXE binary; the chainloaded iPXE script then pulls its boot assets from the
local `lifecycle/ipxe` HTTP service.

## Role — complements `lifecycle/ipxe`, does not replace it

This is the **Design B hybrid** (ADR-0005 / docs #83). The two lifecycle boot
components split the job:

| Component | Layer | Responsibility |
|---|---|---|
| `lifecycle/booter` (this) | L2 / DHCP | **proxyDHCP**: answers PXE discovery, hands clients the boot filename + next-server, chainloads the iPXE binary. Does **not** lease IPs — it rides alongside the existing DHCP server. |
| `lifecycle/ipxe` | L7 / HTTP | Serves the static iPXE script + Talos boot assets (offline-capable). booter points clients here. |

```
bare-metal node (PXE)
   │ 1. broadcasts DHCP/PXE discover on the boot VLAN
   ▼
booter (this pod, proxyDHCP, hostNetwork)
   │ 2. answers with boot filename + chainloads the iPXE binary
   ▼
iPXE
   │ 3. HTTP GET http://ipxe.<ns>.svc/boot.ipxe   (lifecycle/ipxe)
   ▼
Talos boots
```

booter complements ipxe — it does **not** replace it. Removing booter does not
remove the HTTP boot-asset path; removing ipxe leaves booter with nothing to
chainload to. Both are needed for an offline-capable bare-metal boot.

## Contents

| Resource | Function |
|---|---|
| `Namespace booter` | Component boundary. PSA `privileged` — proxyDHCP needs hostNetwork + UDP < 1024. |
| `ServiceAccount booter` | Identity for the Deployment (no RBAC needed). |
| `ConfigMap booter-config` | Default skeleton with a placeholder proxyDHCP config. The consumer repo (`talos-seeder-cluster`) overrides `.data` with the real config. |
| `Deployment booter` | `siderolabs/booter` pinned to `v0.3.1`, `hostNetwork: true`, caps reduced to `NET_BIND_SERVICE` + `NET_RAW` (not privileged), singleton (`replicas: 1`, `Recreate`). |

No `Service` object: proxyDHCP communicates over the host network (raw L2
broadcast), so a ClusterIP/LoadBalancer Service would not carry its traffic.

## Consumer-supplied config

The catalog ships only the workload shell + a documented placeholder. The
consumer cluster repo (`talos-seeder-cluster`, Layer 3) supplies:

- **Real `booter-config` ConfigMap** — boot interface/VLAN, the iPXE binaries to
  serve (BIOS `undionly.kpxe` / UEFI `ipxe.efi`), the `lifecycle/ipxe` HTTP
  next-URL, and the allowed client MACs / VLAN scope.
- **`nodeSelector`** pinning booter onto the node attached to the boot VLAN — a
  proxyDHCP responder is a singleton on its segment; a second one would
  double-answer discovery.
- **DHCP coordination** on the UCG so booter rides proxyDHCP alongside the
  primary DHCP server (proxyDHCP does not lease addresses).

## Open questions (resolve in the consumer overlay)

booter's standalone (non-Omni) usage is sparsely documented upstream. The catalog
makes deliberate, documented defaults; the consumer finalizes them:

- **Exact invocation** — the Deployment mounts the config at `/etc/booter/` and
  passes `--config=/etc/booter/booter.yaml`. If a given booter build expects env
  vars or different flags, the consumer overlay overrides `args` (same skeleton
  split as `lifecycle/ipxe`).
- **Ports** — UDP 67 (DHCP), 69 (TFTP), 4011 (proxyDHCP) are declared on the
  pod; with `hostNetwork` they bind directly on the node.

## Sync-Wave Position

`sync-wave: "0"` — independent of Crossplane/providers/compositions. Runs in
parallel with `lifecycle/ipxe`.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/booter:vX.Y.Z
```

## Related ADRs

- [ADR-0005 — Bare-Metal-PXE-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0005-bare-metal-pxe-strategy.md)
