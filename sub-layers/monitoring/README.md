# Sub-Layer `monitoring`

LGTM-A-Stack (Loki + Grafana + Tempo + Mimir + Alloy) + kube-prometheus-stack (operator-only).

OCI-Distribution pro Komponente (ADR-0009). Konsumenten-Cluster wählen das Subset (Seeder = Operator + Alloy-Forwarder, DHQ = Vollstack).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`kube-prometheus-stack`](components/kube-prometheus-stack/) | 0 | Helm `prometheus-community/kube-prometheus-stack` (Prometheus disabled) | `oci://.../monitoring/kube-prometheus-stack:vX.Y.Z` |
| [`loki`](components/loki/) | 10 | Helm `grafana/loki` (distributed) | `oci://.../monitoring/loki:vX.Y.Z` |
| [`mimir`](components/mimir/) | 10 | Helm `grafana/mimir-distributed` | `oci://.../monitoring/mimir:vX.Y.Z` |
| [`tempo`](components/tempo/) | 10 | Helm `grafana/tempo-distributed` | `oci://.../monitoring/tempo:vX.Y.Z` |
| [`alloy`](components/alloy/) | 20 | Helm `grafana/alloy` (DaemonSet) | `oci://.../monitoring/alloy:vX.Y.Z` |
| [`grafana`](components/grafana/) | 20 | Helm `grafana/grafana`, OIDC via Dex | `oci://.../monitoring/grafana:vX.Y.Z` |

Wave 0: Operator + CRDs. Wave 10: drei Storage-Endpoints (alle gegen Garage). Wave 20: Collector + UI (brauchen Endpoints aus Wave 10).

Bidirektionale Watchdog-AlertmanagerConfig (Seeder ↔ DHQ) lebt aktuell als Cross-Cluster-Resource im Konsumenten-Repo — sobald Issue #36 implementiert ist, kann das eine eigene `monitoring/watchdog`-Komponente werden.

## Konsumiert von

- **DHQ** — Vollstack
- **Seeder** — Subset: `kube-prometheus-stack` + `alloy` (Forwarder zu DHQ-Endpoints)

## Backlog-Issue

[#17 — Sub-Layer `monitoring/`: LGTM-A](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring)

Verwandt: [#34 — DHQ-LGTM-A-Monitoring-Stack](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DHQ-LGTM-A), [#35 — Seeder-LGTM-A-Subset](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Seeder-LGTM-A), [#36 — Bidirektionale Watchdog-Webhooks](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Watchdog-Webhooks).

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
