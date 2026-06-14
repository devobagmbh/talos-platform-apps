# Komponente `databases/valkey-operator`

**[hyperspike/valkey-operator](https://github.com/hyperspike/valkey-operator)** — bringt das `valkeys.hyperspike.io/v1` (`Valkey`) CRD + den Operator-Controller. Realisiert die Capability **`redis-managed`** über **Valkey** (BSD-3, Linux-Foundation-Fork von Redis 7.2; wire-protocol-kompatibel auf Port 6379).

> **Warum Valkey statt Redis?** Redis ist seit 2024 RSALv2/SSPL. Harbor selbst migriert offiziell von Redis auf Valkey (goharbor/harbor#22935, Ziel 2.16). Der klassische `spotahome/redis-operator` ist de facto tot (letztes Stable 12/2022). Valkey + hyperspike ist lizenzsauber und Harbor-Roadmap-konform. (apps #83, Entscheidung Robert 2026-06-09.)
>
> **Komponentenname:** `valkey-operator` (nicht der Issue-Platzhalter `redis-operator`) — die Komponente ist ehrlich das, was sie deployt. Die Capability heißt weiterhin `redis-managed` (protokoll-orientiert).

- **OCI-Pfad:** `oci://ghcr.io/devobagmbh/talos-platform-apps/databases/valkey-operator:vX.Y.Z`
- **sync-wave:** `0` — bringt das `Valkey`-CRD, das konsumierende Apps (Harbor-Cache) brauchen
- **Quelle:** vendored Release-`install.yaml` v0.0.61 (raw manifests; kein Helm)

## Operator vs. CR

Diese Komponente liefert **nur den Operator** (CRD + controller-manager + RBAC + ns `valkey-operator-system`). Konkrete `Valkey`-CRs sind **consumer-owned** (ADR-0024) und gehören in den jeweiligen App-Sub-Layer / das Cluster-Repo — z.B. Harbors Cache (apps #84, Wiring im Konsumenten-Repo).

## Talos / Single-Node

- **Kein cert-manager nötig** — der Operator hat keine admission webhooks. cert-manager wird erst zur Abhängigkeit, wenn eine `Valkey`-CR `spec.tls: true` mit `certIssuer` setzt (für den cluster-internen Harbor-Cache nicht der Fall).
- **Cluster-Modus immer** (kein echter Standalone): `nodes: 1` = ein Valkey-Server, der alle 16384 Slots hält. Bei einem einzelnen Node entstehen praktisch keine MOVED-Redirects → mit Harbors Redis-Client testen.
- **Reife:** pre-1.0 (v0.0.61). Bekannte Einschränkung: `replicas > 0` erzeugt derzeit zusätzliche Primaries statt echter Replicas (upstream #186) → für Single-Node `replicas: 0` lassen. Für einen unkritischen Cache vertretbar, **nicht** als zustandskritischer Primärspeicher.

## Beispiel-`Valkey`-CR (Referenz — NICHT Teil dieser Komponente)

```yaml
apiVersion: hyperspike.io/v1
kind: Valkey
metadata:
  name: harbor-cache
  namespace: harbor
spec:
  nodes: 1            # single node, all slots local
  replicas: 0         # see upstream #186
  tls: false          # no cert-manager
  prometheus: false
  volumePermissions: true
  storage:
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: synology-iscsi-storage
      resources: { requests: { storage: 8Gi } }
```

Der Operator legt für eine CR ohne `anonymousAuth` automatisch ein gleichnamiges Secret (`data.password`, 16 Zeichen) an; Harbor referenziert dieses als `REDIS_PASSWORD` (Wiring in #84).

## Verwandte ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0024 — Customization Contract](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md)
