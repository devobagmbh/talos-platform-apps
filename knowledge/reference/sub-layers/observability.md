---
type: reference
title: observability sub-layer
description: The LGTM-A telemetry stack, Prometheus/Grafana operators, exporters, and Hubble.
tags: [reference, sub-layer, observability]
timestamp: 2026-07-11
sources:
  - sub-layers/observability/README.md
  - sub-layers/observability/compatibility.yaml
---

# observability sub-layer

The Loki/Grafana/Tempo/Mimir/Alloy (LGTM-A) stack plus the Prometheus and Grafana
operators, node/state/blackbox/DCGM exporters, metrics-server, and Hubble. OCI
prefix: `ghcr.io/devobagmbh/talos-platform-apps/observability/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| prometheus-operator-crds | -1 | `-crds` half | - | - |
| grafana-operator-crds | -1 | `-crds` half | - | - |
| prometheus-operator | 0 | - | - | observability/prometheus-operator-crds |
| grafana-operator | 0 | - | - | observability/grafana-operator-crds |
| hubble | 0 | - | `network-observability` (drop-in) | - |
| metrics-server | 0 | - | `hpa-metrics` (drop-in) | - |
| kube-state-metrics | 0 | - | - | - |
| node-exporter | 0 | - | - | - |
| blackbox-exporter | 0 | - | - | - |
| nvidia-dcgm-exporter | 0 | - | `gpu-runtime` (rewrite-required) | - |
| loki | 10 | - | `logs-storage` (data-migration), `logs-query` (drop-in) | `s3-object` (cap) |
| mimir | 10 | - | `metrics-storage` (data-migration), `metrics-query` (drop-in) | `s3-object` (cap) |
| tempo | 10 | - | `traces-storage` (data-migration), `traces-query` (drop-in) | `s3-object` (cap) |
| alloy | 20 | - | `logs-collect` (label-move), `metrics-scrape` (drop-in), `traces-collect` (label-move) | loki, mimir, tempo |
| grafana | 20 | - | `dashboards` (label-move) | loki, mimir, tempo |

## Sync-wave order

CRDs (-1) → operators + exporters (0) → LGTM backends (10, require `s3-object`) →
collection + Grafana (20). `kube-prometheus-stack` is a *stack* (a composition of
these components), documented in the sub-layer README, not a component of its own.

## Notes

- strict-B `-crds` halves: `prometheus-operator-crds`, `grafana-operator-crds`.
- `loki`/`mimir`/`tempo` carry populated freeze-lines (env + secret keys for their object-store backend).
- Gap (tracked in issue #523): `grafana` lacks a `customization.yaml`; `hubble` README omits OCI path / sync-wave / ADR references.
