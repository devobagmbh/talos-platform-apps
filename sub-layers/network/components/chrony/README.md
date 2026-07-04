# Component `network/chrony`

[chrony](https://chrony-project.org/) — a bespoke **in-cluster NTP time server**.
A single central Deployment fronted by a `LoadBalancer` Service on `123/UDP`
serves valid NTP time (RFC 5905) to KubeVirt VMs and external LAN/IoT devices. It
runs in **serve-only** mode: it answers NTP queries but never disciplines any
system clock, so it cannot collide with the Talos substrate's node time
management. Published as an independently versioned OCI artifact (ADR-0009).

This is a **bespoke, hand-authored `manifests/` component with no `helm/`
directory**: no maintained in-cluster NTP Helm chart exists. It ships **zero**
`CustomResourceDefinition` (ADR-0028 strict-B split is N/A).

This component implements the **`ntp-service`** capability
(`compatibility.yaml` → `provides[].capabilities: [{id: ntp-service, swap_class:
consumer-change}]`). The stable interface is the NTP wire protocol (`123/UDP`);
chrony, ntpd, and openntpd are swappable implementations of it. The swap cost is
`consumer-change` because the freeze-line exposes a tool-specific `chrony.conf`
that a consumer would have to rewrite to swap the daemon (see
`catalog/capability-index.yaml`, domain `network`).

- **OCI path:** `ghcr.io/devobagmbh/talos-platform-apps/network/chrony`
  (registry tag `X.Y.Z`; git tag `network/chrony-vX.Y.Z`).
- **Sync-wave:** `0` — a leaf service with no catalog-internal ordering
  constraint (`customization.yaml` `sync_wave: "0"`).
- **ADRs:** ADR-0009 (layer model), ADR-0018 (policy + image-CVE gate), ADR-0021
  (capability layer model), ADR-0024 v2 (freeze-line contract), ADR-0028 (N/A —
  no CRDs).

## Contents

The rendered workload (`grep '^kind:' rendered/manifest.yaml`) is:

- `Namespace` (`chrony`, dedicated, `pod-security.kubernetes.io/enforce:
  baseline`) — sole-claimant; the component ships its own namespace.
- `ServiceAccount` (`chrony`, `automountServiceAccountToken: false` — chrony needs
  no API-server access; no RBAC).
- `ConfigMap` (`chrony-config`, key `chrony.conf`) — the catalog-default,
  **inert** configuration (see below).
- `Deployment` (`chrony`, `replicas: 1`) — a single central server, **not** a
  DaemonSet. Container `command: ["/usr/sbin/chronyd"]`, `args: ["-n", "-x", "-f",
  "/etc/chrony.conf"]`.
- `Service` (`chrony`, `type: LoadBalancer`, one port `123/UDP`, `targetPort:
  123`) — no LB-IP annotation (consumer overlay).
- `NetworkPolicy` (`chrony-egress`, `policyTypes: [Egress]`) — egress-only:
  permits `53/UDP`+`53/TCP` (DNS) and `123/UDP` (upstream NTP), default-denies the
  rest.

### Image

Pinned by immutable digest:
`docker.io/cturra/ntp@sha256:7224d4e7c7833aabbcb7dd70c46c8a8dcccda365314c6db047b9b10403ace3bc`
— a minimal, actively-maintained Alpine-based chrony NTP server (chrony
`4.6.1-r1`). Never `:latest`; the digest is authoritative and reproducible. The
image's own entrypoint is bypassed — the workload runs `chronyd` directly with
the serve-only flags above.

## Security posture

- **Serve-only (`-x`)** — `chronyd` reads and serves the system clock but never
  adjusts it, so no clock-control capability is required and there is no collision
  with Talos node time management. `-x` is a **process argument**, not a
  `chrony.conf` directive.
- **NTP-amplification hardening** — the control/monitoring channel is disabled
  (`cmdport 0`, closing the remote-admin / monitoring-request vector) and
  response-rate limiting is enabled (`ratelimit`, against `123/UDP` response
  reflection). The catalog default ships **no client-access grant**, so out of the
  box the server serves nobody and cannot act as an open reflector — it is inert
  until the consumer supplies scoped access grants.
- **Pod hardening (PSA baseline)** — non-root (`runAsNonRoot`, uid `65532`),
  `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop:
  [ALL]` with only `NET_BIND_SERVICE` re-added (the non-root privileged-port bind
  for `123/UDP`), `seccompProfile: RuntimeDefault`. No host namespaces, no
  hostPath, no host port. `enforce: baseline` is the strictest PSA level the pod
  satisfies — Restricted forbids any added capability, so it cannot admit this
  workload.

## Consumer obligations

The catalog ships the signed workload; the consumer OWNS the cluster-specific
configuration and applies it via its Argo overlay. The consumer MUST:

- **Supply client-subnet access grants.** Override the `chrony-config` ConfigMap
  (freeze-line `config` shape, `customization.yaml` `required.config_files`) with
  a `chrony.conf` that grants access to the cluster's client subnets (chrony's
  `allow <CIDR>` directive). Without this the server serves no client.
- **Assign the LoadBalancer IP.** Add the Cilium LB-IPAM annotation
  (`io.cilium/lb-ipam-pool` or a fixed `io.cilium/ip-address`) to the Service via
  the overlay — the catalog ships no IP.
- **Optionally override the upstream source.** The default is `pool pool.ntp.org
  iburst`; an enterprise cluster may prefer a local GPS/atomic source.
- **Optionally ship an ingress NetworkPolicy.** The set of client subnets allowed
  to reach `123/UDP` is cluster-specific and is delivered by the consumer
  alongside the access grants; the catalog ships only the egress policy.

When overriding `chrony.conf`, the consumer MUST **preserve** `cmdport 0` and
`ratelimit`, MUST **NOT** add any clock-stepping/slewing directive (e.g.
`makestep`, `rtcsync`, `maxslewrate`), and MUST **NOT** change the Deployment
`args` — the `-x` serve-only flag is a `chronyd` process argument, not a
`chrony.conf` directive, so a config-only override cannot remove it, but the args
must be kept as shipped. The catalog default only guarantees these properties for
the shipped configuration, not for a consumer-composed override.

**High availability is a consumer concern.** The catalog ships a single-replica
Deployment. A consumer that relies on NTP for VM workloads SHOULD run 2+ replicas
with a PodDisruptionBudget via its overlay; otherwise eviction of the single pod
leaves clients without their NTP source.
