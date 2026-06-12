# observability/hubble

Hubble Day-2 observability for the Cilium CNI: `hubble-relay` (cluster-wide flow
aggregation), `hubble-ui` (web UI), and the `hubble-generate-certs` CronJob
(relay↔server mTLS). Isolated from the Cilium chart and delivered from the apps
catalog, because the Cilium **seed** disables Hubble for a deterministic
inlineManifest render (`talos-platform-base#121`/`#122`).

## Substrate precondition (IMPORTANT — read before deploying)

This component delivers the Hubble **consumers** (relay/ui) and their certs. It
does **not** turn the Hubble **server** on. The server runs inside the
`cilium-agent` and is gated by `enable-hubble: "true"` (+ `hubble-listen-address:
":4244"`) in the `cilium-config` ConfigMap. That is a **Cilium-layer** setting,
not an observability concern — so it is intentionally **out of scope** for this
component.

Until the agent has Hubble enabled, `hubble-relay` will start but find no peer
(`hubble-peer` Service resolves to the agents' `:4244`, which is closed). Enable
the server on the substrate first, via **one** of:

- **Seed (preferred, deterministic):** in the consumer's `cilium_values_override`
  set `hubble.enabled: true` + `hubble.tls.auto.method: cronJob` +
  `hubble.relay.enabled: false` + `hubble.ui.enabled: false`. That gives the agent
  `enable-hubble` with NO template-time cert generation (deterministic seed — see
  `#121`), while relay/ui come from this component.
- **Day-2 Cilium self-management:** once a Cilium self-management mechanism exists
  (none today), `enable-hubble` is set there.

This split is deliberate: the **server** is Cilium substrate; the **relay/UI**
are observability workloads. This component owns only the latter.

## Contents (16 resources, all `kube-system` / cluster-scoped)

| Group | Resources |
|---|---|
| hubble-relay | Deployment, Service, ConfigMap (`hubble-relay-config`), ServiceAccount |
| hubble-ui | Deployment, Service, ConfigMap (`hubble-ui-nginx`), ServiceAccount, ClusterRole(+Binding) |
| certs | CronJob + initial Job (`hubble-generate-certs`), Role(+Binding), ServiceAccount |
| peer | `hubble-peer` Service (selects the agents' `:4244`) |

Images are pinned by digest, version-matched to the Cilium chart
(`hubble-relay:v1.19.4`, `hubble-ui:v0.13.5`, `certgen:v0.4.3`).

## Regenerating (on a Cilium version bump)

`manifests/hubble.yaml` is a curated slice of the Cilium chart (there is no
standalone Hubble chart). Regenerate the **base slice** 1:1, keeping the version in
sync with the Cilium seed in `talos-platform-base`:

```sh
helm template cilium cilium/cilium --version <CILIUM_VERSION> \
  --namespace kube-system --kube-version <K8S_VERSION> --skip-tests \
  --set hubble.enabled=true --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true --set hubble.tls.auto.enabled=true \
  --set hubble.tls.auto.method=cronJob --set 'hubble.tls.auto.schedule=0 0 1 */4 *' \
| yq eval-all 'select((.metadata.name // "") | test("^hubble-(relay|ui|generate-certs|peer)"))' - \
  > manifests/hubble.yaml
```

### Catalog hardening overlay (re-apply after every regeneration)

The upstream slice ships hubble-ui and certgen under-hardened and sets no resource
limits. The catalog adds the following **on top of** the slice — the 1:1 regenerate
above wipes them, so re-apply each (all are marked with a `# Catalog …` comment in
the manifest):

- **Resource requests + memory limits** on every container (relay, ui-frontend,
  ui-backend, certgen Job + CronJob). `requests.{cpu,memory}` + `limits.memory`, no
  CPU limit (avoids throttling).
- **hubble-ui hardening**: `runAsNonRoot: true` + `seccompProfile: RuntimeDefault` at
  pod level; `runAsNonRoot` + `capabilities.drop: [ALL]` + `seccompProfile` on the
  frontend and backend containers (the slice leaves these with only
  `allowPrivilegeEscalation: false`). hubble-relay is already fully hardened upstream.
- **certgen** Job + CronJob: add `runAsNonRoot: true` + `runAsUser`/`runAsGroup: 65532`.
  The certgen image declares no `USER` (runs as root by default), so `runAsNonRoot`
  alone would block container start — an explicit non-root UID is required.
- **hubble-ui backend probes**: `readinessProbe` + `livenessProbe` (tcpSocket :8090) so
  a dead backend surfaces as NotReady instead of a silently empty UI.
- **hubble-relay `terminationGracePeriodSeconds: 15`** (upstream default 1s) to drain
  active flow streams.

Then `task render:one -- observability/hubble` and commit `rendered/manifest.yaml`.

## Cert rotation

The `hubble-generate-certs` CronJob rotates the relay/server mTLS secrets every 4
months; the leaf certs are valid 12 months (3× margin). **No relay restart is
required**: hubble-relay (v1.19.x) hot-reloads TLS certs without dropping
connections — the Cilium `certloader` fetches the keypair per handshake
(`GetConfigForClient` / `GetClientCertificate`) backed by a polling file-watcher that
is safe for Kubernetes projected-secret symlinks. (Confirmed against the v1.19.4
`pkg/crypto/certloader` source and the Cilium Hubble-TLS docs.)

## Verification (local)

Run in the `local/` Talos-docker setup: enable the agent Hubble server (seed
override above), then deploy this component. The relay/ui probes test the relay's own
gRPC server (`:4222`), **not** peer connectivity — so "Ready" alone does not prove the
relay reached the agents' `:4244`. Confirm the peer link explicitly:

```sh
# at least one peer must be connected; "0 peers" means the substrate precondition
# (enable-hubble on the agent) was not met — distinct from "connected but no traffic".
kubectl exec -n kube-system deploy/hubble-relay -- hubble status
```

Then confirm `cilium hubble` / the UI shows flows once a workload generates traffic.
Live verification belongs in the local cluster, not CI.
