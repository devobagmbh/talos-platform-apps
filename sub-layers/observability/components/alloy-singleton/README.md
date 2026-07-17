# alloy-singleton

Grafana Alloy deployed as a **single-replica Deployment** that watches the cluster's
Kubernetes Events (`core/v1` Events) and forwards them to a logs sink
(`observability/loki`). This is the [`events-collect`](../../../../catalog/capability-index.yaml)
capability implementation.

## What ships

- A Grafana **Alloy Deployment** (`controller.type: deployment`,
  `controller.replicas: 1`) rendered from the upstream `grafana/alloy` chart
  `1.10.0` (appVersion `v1.17.0`), plus its `Service` and `ServiceAccount`.
- A dedicated **Namespace** `alloy-singleton` with `pod-security.kubernetes.io/enforce: restricted`
  (`manifests/00-namespace.yaml`).
- A hand-authored, minimal **ClusterRole + ClusterRoleBinding** (`manifests/10-rbac.yaml`)
  granting `get`/`list`/`watch` on core `events` **only** — the chart's broader RBAC
  is suppressed (`rbac.create: false`).

The workload ships **no CRDs** (`crds.create: false`); ADR-0028 strict-B does not
apply, so there is no `-crds` sibling artifact.

## Why a singleton

The Kubernetes Event stream is shared cluster state. Exactly **one** collector must
watch it — a clustered or DaemonSet topology would double-ingest every Event. Hence a
`Deployment` with `replicas: 1` and Alloy **clustering disabled**
(`alloy.clustering.enabled: false`), distinct from the node-local `observability/alloy`
DaemonSet that collects pod logs, metrics, and traces. There is **no
PodDisruptionBudget** — a single-replica singleton has no availability budget to
protect.

## OCI path

```text
ghcr.io/devobagmbh/talos-platform-apps/observability/alloy-singleton
```

Published tag `X.Y.Z` (bare SemVer); git tag `observability/alloy-singleton-vX.Y.Z`.

## Sync-wave

`20` — deploys after its Loki sink (`observability/loki`).

## Namespace & Pod Security

The workload runs in the dedicated `alloy-singleton` namespace at PSA level
`restricted`. Events are read through the Kubernetes API + the minimal ClusterRole; the
workload mounts no host paths and uses no host namespaces, so it satisfies `restricted`:
the pod sets `runAsNonRoot` + `seccompProfile: RuntimeDefault`, and both containers
(alloy + config-reloader) set `allowPrivilegeEscalation: false` and
`capabilities.drop: [ALL]`.

## Consumer obligations

The consumer owns the pipeline config (ADR-0024 Shape b — the catalog ships **no**
config):

1. Author a ConfigMap named **`alloy-singleton-config`** in the `alloy-singleton`
   namespace with a **`config.alloy`** key. The workload mounts it at
   `/etc/alloy/config.alloy`.
2. The config authors a `loki.source.kubernetes_events` source that watches cluster
   Events and a `loki.write` sink pointing at the cluster's `observability/loki`
   endpoint. Cross-cluster Loki endpoints needing credentials move the credential
   portion to a separate Shape (c) Secret — never a plain ConfigMap.
3. Wire the Argo `Application` (consumer repo) with the sync-wave-`20` annotation; add
   the PNI trust-anchor labels, the `pod-security.kubernetes.io/enforce-version` pin,
   and audit/warn modes in the namespace overlay.

See `customization.yaml` for the machine-readable freeze-line contract.

## ADR references

- [ADR-0024](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-catalog-customization-contract.md) — customization contract, freeze-line **Shape (b)** (consumer-authored config file).
- [ADR-0009](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) — multi-layer OCI distribution; component is the OCI unit.
- [ADR-0021](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md) — capability-first contracts (`events-collect`).
