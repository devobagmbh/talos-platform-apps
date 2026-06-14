# Sub-Layer `observability`

LGTM-A-Stack (Loki + Grafana + Tempo + Mimir + Alloy) + kube-prometheus-stack (operator-only) + Hubble (Cilium network-flow visibility).

OCI-Distribution pro Komponente (ADR-0009). Konsumenten-Cluster wählen das Subset (Seeder = Operator + Alloy-Forwarder, Office-Lab = Vollstack).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`prometheus-operator-crds`](components/prometheus-operator-crds/) | -1 | Helm `prometheus-community/prometheus-operator-crds` (strict-B CRDs artifact, ADR-0028) | `oci://.../observability/prometheus-operator-crds:vX.Y.Z` |
| [`kube-prometheus-stack`](components/kube-prometheus-stack/) | 0 | Helm `prometheus-community/kube-prometheus-stack` (Prometheus disabled) | `oci://.../observability/kube-prometheus-stack:vX.Y.Z` |
| [`loki`](components/loki/) | 10 | Helm `grafana/loki` (distributed) | `oci://.../observability/loki:vX.Y.Z` |
| [`mimir`](components/mimir/) | 10 | Helm `grafana/mimir-distributed` | `oci://.../observability/mimir:vX.Y.Z` |
| [`tempo`](components/tempo/) | 10 | Helm `grafana/tempo-distributed` | `oci://.../observability/tempo:vX.Y.Z` |
| [`alloy`](components/alloy/) | 20 | Helm `grafana/alloy` (DaemonSet) | `oci://.../observability/alloy:vX.Y.Z` |
| [`grafana`](components/grafana/) | 20 | Helm `grafana/grafana`, OIDC via Dex | `oci://.../observability/grafana:vX.Y.Z` |
| [`hubble`](components/hubble/) | 0 | Curated slice of Helm `cilium/cilium` (relay/ui/certs) | `oci://.../observability/hubble:vX.Y.Z` |

Wave -1: `prometheus-operator-crds` (strict-B CRDs artifact, ADR-0028 — `monitoring.coreos.com` CRDs land before any controller or consumer CR). Wave 0: Operator-Workload + Hubble. Wave 10: drei Storage-Endpoints (alle gegen Garage). Wave 20: Collector + UI (brauchen Endpoints aus Wave 10).

`hubble` ist orthogonal zum LGTM-A-Stack (Netzwerk-Flow-Sichtbarkeit aus dem Cilium-Substrat, nicht Logs/Metrics/Traces) und hängt nur vom Cilium-Agent-Hubble-Server ab — siehe [`components/hubble/`](components/hubble/) für die Substrat-Precondition.

Bidirektionale Watchdog-AlertmanagerConfig (Seeder ↔ Office-Lab) lebt aktuell als Cross-Cluster-Resource im Konsumenten-Repo — sobald Issue #36 implementiert ist, kann das eine eigene `observability/watchdog`-Komponente werden.

## Konsumiert von

- **Office-Lab** — Vollstack
- **Seeder** — Subset: `kube-prometheus-stack` + `alloy` (Forwarder zu Office-Lab-Endpoints)

## Backlog-Issue

[#17 — Sub-Layer `observability/`: LGTM-A](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring)

Verwandt: [#34 — Office-Lab-LGTM-A-Monitoring-Stack](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Office-Lab-LGTM-A), [#35 — Seeder-LGTM-A-Subset](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Seeder-LGTM-A), [#36 — Bidirektionale Watchdog-Webhooks](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Watchdog-Webhooks).

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
