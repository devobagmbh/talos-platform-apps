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
  restricted`) — sole-claimant; the component ships its own namespace.
- `ServiceAccount` (`chrony`, `automountServiceAccountToken: false` — chrony needs
  no API-server access; no RBAC).
- `Deployment` (`chrony`, `replicas: 1`) — a single central server, **not** a
  DaemonSet. Container `command: ["/usr/sbin/chronyd"]`, `args: ["-n", "-x", "-U",
  "-f", "/etc/chrony.conf"]`. It mounts `/etc/chrony.conf` (subPath `chrony.conf`)
  from
  the **consumer-provided** ConfigMap `chrony-config`, which is intentionally NOT
  in the shipped manifests (the render is workload-only).
- `Service` (`chrony`, `type: LoadBalancer`, one port `123/UDP`, `targetPort:
  123`) — no LB-IP annotation (consumer overlay).

### Image

Pinned by immutable digest:
`docker.io/dockurr/chrony@sha256:9ee7c0c9ba91d65c4fe9b9b45577a3c1470a887656cafec0b605b96c7b433d0a`
— a minimal Alpine-based chrony NTP server (chrony `4.8-r7`). Never `:latest`;
the digest is authoritative and reproducible. The pinned image is **CVE-clean**
(0 HIGH/CRITICAL, 0 vulnerabilities all severities; Alpine 3.24, chrony `4.8`),
verified by the image-CVE gate (ADR-0018). The base tracks Alpine's rolling
`edge` line, which is why it ships freshly patched packages; the immutable digest
pin keeps that state authoritative and reproducible. The image's own entrypoint
(`/entrypoint.sh`) is bypassed — the workload runs `chronyd` directly with the
serve-only flags above.

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
- **Non-root operation depends on the `-U` process argument** — chronyd refuses
  to start as a non-root user and fatals `Not superuser` unless told otherwise.
  The `-U` argument disables that root-privilege check, allowing chronyd to run
  under the non-root `runAsUser` (uid `65532`). This is safe precisely because the
  workload is already serve-only: `-x` disables all clock discipline (no
  `CAP_SYS_TIME` is granted), and the single re-added `NET_BIND_SERVICE` capability
  is only what a non-root process needs to bind the privileged `123/UDP` port. `-U`
  therefore relaxes chronyd's own uid self-check WITHOUT weakening the pod's
  hardening — no root, no added capability, no PSA downgrade.
- **Pod hardening (PSA restricted)** — non-root (`runAsNonRoot`, uid `65532`),
  `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop:
  [ALL]` with only `NET_BIND_SERVICE` re-added (the non-root privileged-port bind
  for `123/UDP`), `seccompProfile: RuntimeDefault` (pod + container). No host
  namespaces, no hostPath, no host port. `enforce: restricted` is the strictest
  PSA level the pod satisfies — the workload meets every Restricted hardening
  control, and Restricted permits the single `NET_BIND_SERVICE` capability it
  adds.

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

- **Give chronyd a synchronization source, or it serves nothing.** A chrony
  server answers clients only once it is itself synchronized. The
  consumer-provided `chrony.conf` **MUST** carry either a reachable upstream
  (a `pool`/`server` directive — e.g. the `pool pool.ntp.org iburst` in the
  starting point above) **OR** a `local stratum N` directive (which lets chronyd
  serve from its own clock as a last-resort island source). With neither,
  chronyd runs (the pod is Healthy) but never reaches a synchronized state and
  therefore serves no valid time to clients.
- **Assign the LoadBalancer IP.** Add the Cilium LB-IPAM annotation
  (`io.cilium/lb-ipam-pool` or a fixed `io.cilium/ip-address`) to the Service via
  the overlay — the catalog ships no IP.
- **High availability is a consumer concern.** The catalog ships a single-replica
  Deployment. A consumer that relies on NTP for VM workloads SHOULD run 2+
  replicas with a PodDisruptionBudget via its overlay; otherwise eviction of the
  single pod leaves clients without their NTP source.
