# Sub-Layer `monitoring`

LGTM-A-Stack (Loki + Grafana + Tempo + Mimir + Alloy) + kube-prometheus-stack (operator-only).

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| Grafana-Alloy | Helm `grafana/alloy` | DaemonSet als unified Telemetry-Collector (ersetzt Promtail) |
| Loki | Helm `grafana/loki` (distributed-Mode) | Log-Aggregation, Garage-S3-Backend (Chunks) |
| Mimir | Helm `grafana/mimir-distributed` | Metric-Storage, Garage-S3-Backend (Blocks) |
| Tempo | Helm `grafana/tempo-distributed` | Trace-Storage, Garage-S3-Backend (Blocks) |
| Grafana | Helm `grafana/grafana` | Dashboards + Alerts-UI |
| kube-prometheus-stack | Helm `prometheus-community/kube-prometheus-stack` (Prometheus disabled — Mimir ersetzt) | nur Operator + CRDs für ServiceMonitor/PodMonitor/PrometheusRule |
| Alertmanager (DHQ) | aus kube-prometheus-stack | lokale Alerts |
| Alertmanager (Seeder) | aus kube-prometheus-stack | Watchdog für DHQ-AM-Health |

## Konsumiert von

- **DHQ** — Vollstack inklusive Grafana-UI und beiden Alertmanagern.
- **Seeder** — Subset: nur kube-prometheus-stack-Operator + Alertmanager-Watchdog + Alloy-Collector. Loki/Mimir/Tempo werden auf DHQ konsolidiert; Seeder sendet seine Telemetrie via Alloy zu DHQ-Endpoints.

## Inhalt

- `helm/alloy.yaml` — DaemonSet-Konfig, Sources (kubernetes-pods, journald, otelhttp)
- `helm/loki.yaml` — distributed-Mode, Garage-Buckets `loki-chunks` und `loki-ruler`
- `helm/mimir.yaml` — distributed, Garage-Bucket `mimir-blocks`
- `helm/tempo.yaml` — distributed, Garage-Bucket `tempo-blocks`
- `helm/grafana.yaml` — Datasources auf Loki/Mimir/Tempo, OIDC via Dex
- `helm/kube-prometheus-stack.yaml` — Prometheus disabled, nur Operator
- `manifests/watchdog-alertmanagerconfig.yaml` — bidirektionale Heartbeat-Receivers Seeder ↔ DHQ
- `manifests/garage-buckets.yaml` — Garage-Bucket-Definitionen (oder über `garage`-Sub-Layer referenziert)

## Backlog-Issue

[#17 — Sub-Layer `monitoring/`: LGTM-A](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring)

Verwandt: [#34 — DHQ-LGTM-A-Monitoring-Stack](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DHQ-LGTM-A), [#35 — Seeder-LGTM-A-Subset](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Seeder-LGTM-A), [#36 — Bidirektionale Watchdog-Webhooks](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Watchdog-Webhooks).

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur (bidirektionales 2-Alertmanager-Pattern)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0007 — Platform-Object-Store (Garage als Backend)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
