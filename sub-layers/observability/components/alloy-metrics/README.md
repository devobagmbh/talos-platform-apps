# Component `observability/alloy-metrics`

A **clustered** [Grafana Alloy](https://grafana.com/docs/alloy/latest/) collector
(OSS, Apache 2.0) scoped to a single role: Prometheus-format metric discovery via
`prometheus.operator.*` (ServiceMonitor/PodMonitor/Probe/ScrapeConfig). Part of the
role-scoped Alloy split (epic #649): the all-in-one
[`observability/alloy`](../alloy/README.md) `DaemonSet` re-scrapes every discovered
target on every node, duplicating each scrape N times across the cluster. This
component instead runs as a **StatefulSet** with `alloy.clustering.enabled: true`,
so discovery targets are sharded across replicas rather than re-scraped by every
node.

It implements **one** capability in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Prometheus-format metrics scrape | `metrics-scrape` | `drop-in` |

This is a **second** implementation of `metrics-scrape` alongside the DaemonSet
`observability/alloy` component (the index is tool-keyed — `grafana-alloy` — not
component-keyed, so both role-scoped deployments of the same tool legitimately
claim it). A consumer picks one, the other, or both depending on which discovery
topology it needs.

## Contents

A `kind: helm` wrapper over the `alloy` chart
(`https://grafana.github.io/helm-charts`, version `1.10.0`, appVersion `v1.17.0`)
plus hand-shipped `manifests/`:

- A `StatefulSet` (`alloy-metrics`) with the chart's config-reloader sidecar, a
  headless `alloy-metrics-cluster` Service (`clusterIP: None`) for
  cluster-membership discovery, a `ServiceAccount` (`alloy-metrics`), and the
  scope-down `ClusterRole`/`ClusterRoleBinding` this discovery role needs
  (`manifests/10-rbac.yaml` — the chart's own broader default RBAC is disabled via
  `rbac.create: false`).
- A dedicated `alloy-metrics` `Namespace` carrying
  `pod-security.kubernetes.io/enforce: restricted`.

The Alloy image is pinned to the chart's appVersion
(`docker.io/grafana/alloy:v1.17.0`); the config-reloader image is pinned to a
SHA256 digest by the chart — never `:latest`.

The chart's `crds` subchart (`crds.create`) is disabled: this component ships **no**
CustomResourceDefinitions, so strict-B (ADR-0028) does not apply and there is no
`-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Freeze-line (ADR-0024 v2, Shape b)

alloy-metrics is **not** cluster-agnostic: its pipeline — the
ServiceMonitor/PodMonitor discovery rules and the Mimir remote-write endpoint — is
cluster-specific and differs per consumer. The freeze-line therefore splits
ownership as Shape (b): the **workload** (the rendered StatefulSet) is
catalog-owned and signed; the **config** is 100% consumer-owned.

The workload mounts an EXISTING consumer-supplied ConfigMap
`alloy-metrics-config` (key `config.alloy`) at `/etc/alloy` and runs
`/etc/alloy/config.alloy` (`alloy.configMap.create: false`). The consumer owns the
whole `config.alloy` file; the signed workload is never patched.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships
none of these:

- **`alloy-metrics-config` ConfigMap** with a `config.alloy` key carrying the full
  discovery + scrape + remote-write pipeline — typically
  `prometheus.operator.servicemonitors` / `prometheus.operator.podmonitors` /
  `prometheus.operator.probes` / `prometheus.operator.scrapeconfigs` components
  feeding a `prometheus.remote_write` block pointed at the cluster's Mimir
  endpoint. That endpoint URL is cluster-specific and lives nowhere in the
  catalog. **`prometheus.operator.scrapeconfigs` is EXPERIMENTAL upstream** —
  the workload sets `alloy.stabilityLevel: "experimental"` (see
  `helm/alloy-metrics.yaml`) specifically so this component is usable; without
  that flag Alloy refuses to load a `config.alloy` that references it. **A
  no-op stub** the consumer can start from before wiring real discovery (see
  §Risks / build notes below for why this matters at sync time):

  ```river
  // config.alloy — minimal stub; replace with real discovery + remote_write.
  prometheus.remote_write "mimir" {
    endpoint {
      url = "http://mimir-nginx.mimir.svc.cluster.local/api/v1/push"
    }
  }
  ```

- **Replica count for live sharding** — `controller.replicas` via
  `source.kustomize.patches`. The catalog ships the chart default (`1`); at a
  single replica, clustering is technically active (the headless Service and
  `--cluster.enabled` args are always rendered) but has nothing to shard across.
  Raise replicas to realize the sharding this component exists for.
- **PodDisruptionBudget** — the catalog ships none. A `minAvailable: 1` PDB at the
  default `replicas: 1` would block all voluntary disruption (draining, node
  upgrades) since there is no second pod to fail over to. A consumer overlaying
  `replicas >= 2` adds its own PDB in the same overlay.
- **Node scheduling** — `tolerations` / `nodeSelector` belong in the consumer Helm
  values overlay; the catalog leaves them at the chart defaults.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors and the pod
  `platform.io/capability-provider.*` labels, plus the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor)
  and the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

## Namespace & Pod Security

The component ships a dedicated `alloy-metrics` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule) carrying
`pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`restricted` is the posture the workload provably satisfies — confirmed against
the rendered StatefulSet pod template: the pod sets `runAsNonRoot: true` +
`seccompProfile: RuntimeDefault`, and **both** containers (`alloy` and
`config-reloader`) set `allowPrivilegeEscalation: false` + `capabilities.drop:
[ALL]` (+ `readOnlyRootFilesystem`, `runAsNonRoot`, `runAsUser: 473`). The
workload ships **no** host mounts (`mounts.varlog` / `mounts.dockercontainers`,
`hostNetwork`, `hostPID` all `false`): discovery + scraping happen through the
Kubernetes API and the network, neither of which needs host access.

## RBAC posture

The component ships a **scope-down** cluster-scoped read `ClusterRole`
(`manifests/10-rbac.yaml`; `rbac.create: false` disables the chart's own broader
default). It grants **read-only** (`get`/`list`/`watch`, never write) on exactly
what the `prometheus.operator.*` discovery components need:

- core: `pods`, `services`, `endpoints`, `secrets`, `configmaps`
- `monitoring.coreos.com`: `servicemonitors`, `podmonitors`, `probes`,
  `scrapeconfigs`, `prometheusrules`
- `networking.k8s.io`: `ingresses` — `prometheus.operator.probes` discovers
  targets via Ingress objects referenced by a Probe CR's
  `spec.targets.ingress` (documented prometheus-operator Probe behavior).

**Excluded**, deliberately, versus the chart's default RBAC:

- core `nodes`, `events` — node-local scraping is the node-local role's job,
  served by the existing `observability/alloy` DaemonSet; this cluster-wide
  discovery role has no node-read need.
- `apps/replicasets` — only needed by `otelcol.processor.k8sattributes`, which
  this role does not run.
- `monitoring.coreos.com/alertmanagerconfigs` — only needed by
  `mimir.alerts.kubernetes`, which this role does not run.

The cluster-wide `secrets`/`configmaps` read is **retained deliberately** (CWE-250
reviewed): a ServiceMonitor/PodMonitor `tlsConfig`/`bearerTokenSecret`/`basicAuth`
can reference a CA-bundle ConfigMap OR a credential Secret in the **target's**
namespace — any namespace in the cluster, not just `alloy-metrics` — so a
namespace-scoped Role cannot express this. Posture and bounding controls (broad
but bounded):

- **Read-only** — no `create`/`update`/`patch`/`delete`/`*`; alloy-metrics cannot
  mutate cluster state.
- **`restricted` PSA** on the pod (see above) + the SA token is the pod's only
  credential.
- **Consumer NetworkPolicy** (consumer-owned) bounds egress.
- **Least-privilege opt-in** — a consumer that does not scrape secret-authed
  targets MAY narrow this `ClusterRole` in its overlay (drop
  `secrets`/`configmaps`); the catalog default keeps the full discovery
  capability rather than silently reducing it.

## Clustering & scaling

`alloy.clustering.enabled: true` renders a headless `alloy-metrics-cluster`
Service (`clusterIP: None`) and injects `--cluster.enabled` +
`--cluster.join-addresses=alloy-metrics-cluster` into the alloy container's args —
**even at `controller.replicas: 1`**. Clustering is therefore inert (nothing to
shard across) at the catalog default; a consumer realizes the sharding by
overlaying `controller.replicas >= 2` via `source.kustomize.patches`. The catalog
ships **no PodDisruptionBudget** for exactly this reason — see §Consumer
obligations above.

## Risks / build notes

- **`alloy-metrics-config` must pre-exist before wave-20 sync.** If the consumer
  has not yet authored the ConfigMap when Argo syncs this component, the pod
  enters `CreateContainerConfigError` and stalls the wave. Start from the no-op
  stub in §Consumer obligations rather than deferring the ConfigMap entirely.
- **WAL on `emptyDir` is ephemeral** — documented Alloy behavior (data under
  `storagePath` is lost on pod restart), acceptable for a stateless metric
  forwarding/discovery role.
- **`prometheus-operator-crds` is a documented-soft runtime dependency, NOT a
  hard `external_dependency`.** Without the `monitoring.coreos.com` CRDs
  installed in-cluster, the ClusterRole grants above are syntactically valid but
  there are no ServiceMonitor/PodMonitor/Probe/ScrapeConfig objects for Alloy to
  discover — a silent no-op, not an error. `compatibility.yaml` does not declare
  this because CRD readiness is a deploy-time ordering concern (like the Mimir
  sink), not a build-time dependency.

## Sync-wave

`20` — alloy-metrics forwards to Mimir (wave 10), so it deploys after it.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/alloy-metrics:0.1.0
```

OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is `observability/alloy-metrics-v0.1.0`
(kept distinct — registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
