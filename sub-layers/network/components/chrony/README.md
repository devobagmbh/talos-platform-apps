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

The catalog ships the **hardened workload only** — namespace, ServiceAccount,
Deployment, Service. The `chrony.conf` configuration is **consumer-provided**
(see §Consumer-provided configuration) and no NetworkPolicy is shipped (see
§Network policy). The rendered workload (`grep '^kind:' rendered/manifest.yaml`)
is:

- `Namespace` (`chrony`, dedicated, `pod-security.kubernetes.io/enforce:
  baseline`) — sole-claimant; the component ships its own namespace.
- `ServiceAccount` (`chrony`, `automountServiceAccountToken: false` — chrony needs
  no API-server access; no RBAC).
- `Deployment` (`chrony`, `replicas: 1`) — a single central server, **not** a
  DaemonSet. Container `command: ["/usr/sbin/chronyd"]`, `args: ["-n", "-x", "-f",
  "/etc/chrony.conf"]`. It mounts `/etc/chrony.conf` (subPath `chrony.conf`) from
  the **consumer-provided** ConfigMap `chrony-config`, which is intentionally NOT
  in the shipped manifests (the render is workload-only).
- `Service` (`chrony`, `type: LoadBalancer`, one port `123/UDP`, `targetPort:
  123`) — no LB-IP annotation (consumer overlay).

### Image

Pinned by immutable digest:
`docker.io/cturra/ntp@sha256:7224d4e7c7833aabbcb7dd70c46c8a8dcccda365314c6db047b9b10403ace3bc`
— a minimal Alpine-based chrony NTP server (chrony `4.6.1-r1`). Never `:latest`;
the digest is authoritative and reproducible. The pinned image carries known
base-library CVEs (Alpine/OpenSSL et al.); these are advisory-tracked by the
image-CVE gate (ADR-0018) and remediated by bumping the pinned digest when a
fixed rebuild is published — the digest pin is not a claim of a CVE-free image.
The image's own entrypoint is bypassed — the workload runs `chronyd` directly
with the serve-only flags above.

## Security posture

- **Host-clock safety is catalog-guaranteed, regardless of consumer config** —
  the Deployment runs `chronyd` with the serve-only `-x` **process argument** and
  drops every capability (`capabilities.drop: [ALL]`, only `NET_BIND_SERVICE`
  re-added — **no `CAP_SYS_TIME`**). Together these mean chronyd **cannot** step
  or slew the system clock even if a consumer's `chrony.conf` adds a
  clock-control directive (`makestep`, `rtcsync`, `maxslewrate`, …): the kernel
  denies the `adjtimex`/`clock_settime` calls without `CAP_SYS_TIME`, and `-x`
  disables the code path outright. There is therefore no collision with Talos
  node time management no matter what the consumer configures. `-x` is a process
  argument, not a `chrony.conf` directive, so a config-only override cannot
  remove it.
- **NTP-amplification hardening is a consumer obligation** — the catalog ships
  no `chrony.conf`, so the amplification/reflection controls (`cmdport 0`,
  `ratelimit`, and a client-scoped `allow`) live in the **consumer-provided**
  ConfigMap. See §Consumer-provided configuration for the mandatory hardening
  the consumer's `chrony.conf` MUST carry.
- **Pod hardening (PSA baseline)** — non-root (`runAsNonRoot`, uid `65532`),
  `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop:
  [ALL]` with only `NET_BIND_SERVICE` re-added (the non-root privileged-port bind
  for `123/UDP`), `seccompProfile: RuntimeDefault`. No host namespaces, no
  hostPath, no host port. `enforce: baseline` is the strictest PSA level the pod
  satisfies — Restricted forbids any added capability, so it cannot admit this
  workload.

## Consumer-provided configuration

The consumer owns **100% of the config**: the catalog ships the hardened workload
only, and the consumer OWNS the entire `chrony.conf`, delivered via its Argo overlay. The
Deployment mounts `/etc/chrony.conf` (subPath `chrony.conf`) from a ConfigMap
named **`chrony-config`** in the `chrony` namespace — this is the freeze-line
`config` shape (`customization.yaml` `provided_refs.config: chrony-config` +
`required.config_files`). The consumer **MUST** supply that ConfigMap; without it
the Deployment's config volume has no source and the pod will not start.

Because the server is exposed on `123/UDP` (a LoadBalancer, potentially on a LAN
or beyond), the consumer's `chrony.conf` **MUST** carry the NTP-amplification /
reflection hardening the catalog can no longer ship for it:

- **Client-scoped `allow`** — grant access ONLY to the specific client CIDRs that
  must reach the server (`allow <your-client-CIDR>`). **NEVER `allow all`** on an
  externally-exposed server: an open `allow` turns the server into an NTP
  reflection/amplification source.
- **`cmdport 0`** — disable the control/monitoring channel, closing the
  remote-admin / monitoring-request vector (distinct from the `123/UDP`
  time-service port).
- **`ratelimit`** — enable response-rate limiting as defense-in-depth against
  `123/UDP` response reflection from a spoofed or compromised in-subnet client.

The consumer **MUST NOT** add any clock-stepping/slewing directive (`makestep`,
`rtcsync`, `maxslewrate`, …); host-clock safety is enforced structurally by the
workload regardless (see §Security posture), but a clock-control directive in the
config is still a misconfiguration to avoid.

RECOMMENDED secure `chrony.conf` starting point (adjust the upstream source and
the client CIDR to the cluster):

```conf
# Upstream time source — replace with a local GPS/atomic source on an
# enterprise cluster; pool.ntp.org is a safe public default.
pool pool.ntp.org iburst

# Control/monitoring channel disabled (remote-admin / monitoring-request vector).
cmdport 0

# Response-rate limiting — defense-in-depth against 123/UDP response reflection.
ratelimit

# Frequency-drift estimation on the writable runtime volume (the container root
# filesystem is read-only). chronyd estimates drift but applies NO clock
# correction (the -x process argument disables clock discipline).
driftfile /run/chrony/drift

# Client access — grant ONLY your client subnets. NEVER `allow all` on an
# externally-exposed server (open reflector). Uncomment and scope to your CIDR:
# allow <your-client-CIDR>

# No clock-control directive (makestep / rtcsync / maxslewrate): serving only,
# never disciplining the system clock.
```

### Network policy

The catalog ships **no NetworkPolicy** — no catalog component ships one. If the
consumer enforces network policy (native `NetworkPolicy` or a Cilium
`CiliumNetworkPolicy`), the consumer OWNS both directions:

- **Ingress** — scope `123/UDP` to the cluster's client CIDRs (the same subnets
  the `chrony.conf` `allow` grants).
- **Egress** — permit DNS (`53/UDP` + `53/TCP`, to resolve the upstream pool) and
  the upstream NTP (`123/UDP`) to the configured time source; default-deny the
  rest.

### Other consumer obligations

- **Assign the LoadBalancer IP.** Add the Cilium LB-IPAM annotation
  (`io.cilium/lb-ipam-pool` or a fixed `io.cilium/ip-address`) to the Service via
  the overlay — the catalog ships no IP.
- **High availability is a consumer concern.** The catalog ships a single-replica
  Deployment. A consumer that relies on NTP for VM workloads SHOULD run 2+
  replicas with a PodDisruptionBudget via its overlay; otherwise eviction of the
  single pod leaves clients without their NTP source.
