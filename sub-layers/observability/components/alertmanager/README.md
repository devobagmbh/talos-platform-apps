# Component `observability/alertmanager`

A **catalog CR-template component** (talos-platform-docs ADR-0009): it ships an
**identity-free** [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)
instance + a base routing skeleton + the platform alert rules as **raw Custom
Resources**, not a Helm chart. The consumer overlays cluster topology + real
notification receivers. Same philosophy as the `secrets` sub-layer shipping
identity-free Vault-CR/Policy templates and `databases/cnpg` shipping Cluster-CR
templates: the catalog ships the *shape*, the consumer supplies the *identity*.

The [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
(`observability/prometheus-operator`, the controller) reconciles the shipped
`Alertmanager` CR into a `StatefulSet` at runtime — so **no `Deployment` /
`StatefulSet` is rendered by this artifact**. The rendered manifest is a *set of
Custom Resources only*.

## What ships

Three Custom Resources, classified by their real `kind`:

| File | `kind` | API group | Purpose |
|---|---|---|---|
| `manifests/10-alertmanager.yaml` | `Alertmanager` | `monitoring.coreos.com/v1` | the operator-reconciled instance (`name: platform`) |
| `manifests/20-alertmanagerconfig.yaml` | `AlertmanagerConfig` | `monitoring.coreos.com/v1alpha1` | identity-free base routing skeleton + inhibit rules + placeholder receivers |
| `manifests/30-prometheusrules.yaml` | `PrometheusRule` | `monitoring.coreos.com/v1` | the Watchdog dead-man's-switch + `absent()` data-presence guards + standard platform alerts |

The artifact ships **0** `CustomResourceDefinition` (strict-B, ADR-0028 — the
`monitoring.coreos.com` CRDs are owned by `observability/prometheus-operator-crds`)
and **0** `Namespace` object (shared-namespace sole-claimant rule, below).

### The `Alertmanager` instance (`10-alertmanager.yaml`)

- **Pinned image / version**: `quay.io/prometheus/alertmanager:v0.28.1` with
  `.spec.version: v0.28.1` (consistent; never `:latest`). v0.28.1 matches the
  Alertmanager release line of `prometheus-operator` v0.91.0.
- **`replicas: 1`** is the catalog default. The consumer overlays an HA peer set
  (`>=3`) for production — a per-cluster topology decision (overlay point below).
  At a single replica there is no HA: a rolling restart (image update, node eviction)
  takes the whole alert-routing path — dedup, dispatch, **and the Watchdog
  heartbeat** — offline for the restart window. A peer cluster's Watchdog detects
  that gap (the design intent below), but a single-cluster deployment with no peer has
  no external observer, so the outage is unobserved. Overlay `replicas` to `>=3`
  before wiring real receivers for any production deployment.
- **Security context**: pod-level `runAsNonRoot: true`,
  `seccompProfile.type: RuntimeDefault`, non-root `runAsUser`/`runAsGroup`/`fsGroup`
  = `65534`. Alertmanager needs no host access. The Prometheus Operator additionally
  applies a restrictive *container* securityContext (`allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true`) to the reconciled
  `StatefulSet`
  ([operator API](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#alertmanagerspec)).
  The resulting pods satisfy PSA **`restricted`** (see [Namespace & Pod Security
  Admission](#namespace--pod-security-admission)) — the pod-level fields are rendered
  in this artifact; the container-level fields are operator-applied at runtime and so
  are not visible in the rendered manifest.
- **`alertmanagerConfigSelector`**: `matchLabels.alertmanagerConfig: platform` —
  the operator merges every `AlertmanagerConfig` carrying that label into this
  instance. The shipped base skeleton carries it; the consumer adds further labeled
  configs the same way.
- **`alertmanagerConfigMatcherStrategy.type: None`** — chosen deliberately. This
  is the *platform-wide* routing instance, so `None` keeps the operator from
  auto-injecting a per-namespace `namespace=<ns>` matcher onto each config's routes,
  letting the central base skeleton route **across** namespaces (cluster-wide
  severity + Watchdog routing). The operator default `OnNamespace` would scope every
  config to its own namespace (tenancy enforcement) and defeat a single central
  routing tree. A multi-tenant consumer that wants per-namespace isolation overlays
  this back to `OnNamespace`.
- **`storage`**: a `volumeClaimTemplate` skeleton (1Gi, `ReadWriteOnce`) for
  notification/silence state. `storageClassName` is **omitted** so the cluster
  default `StorageClass` is used — the consumer overlays a specific class if needed
  (no cluster-specific class is hardcoded). The PVC holds the notification-dedup log
  and active silences; this state is transient and self-heals within `repeatInterval`,
  so no cross-cluster backup is required, but consumers should know that PVC loss
  (cluster rebuild, PV replacement) re-fires previously silenced/deduplicated alerts
  on restart — an alert storm, not data loss.

### The base routing `AlertmanagerConfig` (`20-alertmanagerconfig.yaml`)

Labeled `alertmanagerConfig: platform`. Identity-free skeleton:

- **Route tree**: `groupBy: [alertname, cluster, namespace]`; a dedicated
  **Watchdog route** (matches the always-firing `Watchdog` alert → the `watchdog`
  receiver); severity routing (`critical` → `critical`, `warning` → `warning`);
  default → the `null` no-op receiver.
- **Inhibit rule**: a `severity: critical` alert suppresses a matching
  `severity: warning` on equal `[alertname, namespace, cluster]`. The `equal` set
  includes `cluster` — an *external* label the consumer's Prometheus stamps. If
  `spec.externalLabels.cluster` is absent (or differs between the Prometheus and
  Alertmanager paths), the `equal: cluster` match never fires and the inhibit rule is
  silently inoperative: both the critical and the warning are delivered (duplicate
  notifications, **not** silent alert loss). Setting the `cluster` external label
  (overlay point below) is therefore a hard consumer obligation, not just for routing.
- **Receivers**: **placeholders only** — `null`, `watchdog`, `critical`, `warning`
  with **no** integrations, **no** endpoints, **no** `secretKeyRef`, **no**
  credentials. See [Consumer obligation: receivers + secrets](#consumer-obligation-receivers--secrets).

### The platform `PrometheusRule`s (`30-prometheusrules.yaml`)

> **Evaluated by the consumer's Prometheus instance (issue #20), NOT by
> Alertmanager.** They ship here because the Watchdog rule and the Watchdog route
> are two halves of one dead-man's-switch contract.

- the always-firing **`Watchdog`** alert (`expr: vector(1)`, `for: 0m`,
  `severity: none`) — the dead-man's-switch;
- `absent()` **data-presence guards** (Prometheus self-scrape, kube-state-metrics);
- standard platform alerts (crash-loop, deployment replica mismatch, node
  NotReady, PV filling up), all parametrized by the `cluster` external label — no
  cluster name is hardcoded.

**Selector contract**: this `PrometheusRule` carries `role: alert-rules`. The
consumer MUST configure its Prometheus `ruleSelector` to match (e.g.
`matchLabels: {role: alert-rules}`) or relax it (`ruleSelector: {}`), and MUST set
the `cluster` external label on its Prometheus (`spec.externalLabels.cluster`) so
the rules' `cluster` references resolve and fleet-wide routing works.

## Consumer obligation: receivers + secrets

The shipped receivers are **placeholders**. The consumer delivers real
notifications by authoring **its own** labeled `AlertmanagerConfig`
(`alertmanagerConfig: platform`) that defines the real receiver integrations
(Slack/PagerDuty/email/webhook), referencing credentials via `secretKeyRef` to
**consumer-owned** `Secret`s. That consumer config + its secrets are **NOT** part of
this rendered, signed workload — which is exactly why this component declares **no**
`secret_keys` in its freeze-line contract (declaring a secret the rendered manifest
never reads would be a freeze-line defect). No secret material ships in this
artifact.

### Bidirectional 2-Alertmanager Watchdog (cross-cluster dead-man's-switch)

The Watchdog route exists so a *peer cluster* can detect this cluster's silence.
The intended topology is **bidirectional**: cluster A's `watchdog` receiver is
wired (by the consumer) to send the heartbeat to cluster B's Alertmanager, and B's
to A's. Each side alerts on the **absence** of the peer's Watchdog — if A's whole
Prometheus → Alertmanager → notification path dies, B notices the missing heartbeat
(and vice versa). The peer Alertmanager receiver endpoint is per-cluster identity,
so the consumer wires it; the catalog ships only the Watchdog route + rule.

> **Watchdog route-shadowing — a consumer MUST guard against it.** Because
> `alertmanagerConfigMatcherStrategy: None` merges *every* labeled
> `AlertmanagerConfig` into one flat runtime route list, and sub-routes are evaluated
> first-match, a consumer-authored route placed *before* the platform Watchdog route
> can match `alertname: Watchdog` first. A consumer-authored route that can match the
> Watchdog MUST carry `continue: true` (or simply not match `Watchdog`), or it
> short-circuits the heartbeat to the wrong receiver and the cross-cluster
> dead-man's-switch silently stops — the exact failure the Watchdog exists to catch.
> Merge order is not guaranteed across consumer additions, so do not rely on the
> platform route winning by position.

## Kustomize overlay points (per-cluster, ADR-0023/0024 plain-value overlay)

These are cluster identity / topology, overlaid by the consumer via a Kustomize
patch — **not** freeze-line shapes (so they are absent from
[`customization.yaml`](customization.yaml) `required.*`):

| Field | Where | Why consumer-owned |
|---|---|---|
| `.spec.replicas` | `Alertmanager` CR | HA peer count is a per-cluster topology decision (default `1`) |
| `.spec.externalUrl` | `Alertmanager` CR | the public URL Alertmanager is reachable at (cluster identity) |
| `.spec.storage…storageClassName` | `Alertmanager` CR | omitted → cluster-default class; a specific class is cluster-specific |
| `cluster` external label | the consumer's Prometheus `spec.externalLabels` | the cluster identity stamped on every series the rules route by |

## OCI

```text
ghcr.io/devobagmbh/talos-platform-apps/observability/alertmanager
```

Published registry tag `0.1.0` (the `task push` step strips the leading `v`); the
git tag is the distinct `observability/alertmanager-v0.1.0`.

## Sync-wave

`10` — **after** the `prometheus-operator` controller (wave `0`) and its CRDs (the
`-crds` artifact, wave `-1`). The `Alertmanager` CR needs both the controller and
the `monitoring.coreos.com` CRD schemas present before it can reconcile into a
running instance.

## Consumer Argo wiring

The consumer wires one Argo `Application` for this component at
`argocd.argoproj.io/sync-wave: "10"`, after the `prometheus-operator` pair. It
co-locates in the shared `monitoring` namespace (set `CreateNamespace=false` or rely
on the operator's own namespace ownership — this component ships no `Namespace`, see
below). The real receivers + their `Secret`s + the `cluster` external label are the
consumer's composition concern.

## Namespace & Pod Security Admission

This component does **not** ship a `Namespace` object. The Alertmanager instance
co-locates in the shared `monitoring` namespace with `prometheus-operator`, the
Prometheus instance (issue #20), and the LGTM-A stack; under the **sole-claimant
rule** a shared namespace and its PSA label are the **consumer's composition
concern** (Argo `managedNamespaceMetadata`), because two artifacts declaring the
same `Namespace` would make Argo report "managed by multiple Applications".

The consumer MUST label the `monitoring` namespace at **baseline-or-better**; this
component's pods satisfy the strictest level:

```yaml
pod-security.kubernetes.io/enforce: restricted
```

**`restricted` is the derived level.** The `Alertmanager` CR sets pod-level
`runAsNonRoot: true` + `seccompProfile.type: RuntimeDefault` + a non-root
`runAsUser`/`fsGroup` (visible in the rendered manifest), and the Prometheus Operator
applies a restrictive *container* securityContext (`allowPrivilegeEscalation: false`,
`capabilities.drop: [ALL]`, `readOnlyRootFilesystem: true`) to the reconciled
`StatefulSet` at runtime
([operator API](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#alertmanagerspec))
— so the container-level half is not locally verifiable from this artifact. The pods
use no host access, hostPath, host namespace, or host port, so `restricted` rejects
nothing at admission. (The shared namespace's effective level is the strictest among
its co-tenants; this component imposes no floor above `restricted`.)

## Capability

This component provides the **`alert-routing`** capability
(`catalog/capability-index.yaml`), active implementation `alertmanager`, swap class
**`drop-in`** — a consumer could swap the alert-routing implementation
(e.g. grafana-oncall) without a consumer-visible change. This is the catalog's
shippable realization of the `alert-routing` capability whose `active` design was
recorded against the operator-only `prometheus-operator` component.

## Related ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) (CR-template components)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0015 — Monitoring-Architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
