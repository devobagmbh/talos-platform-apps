# Capability-Katalog

`talos-platform-apps` ist der zentrale Plattform-Katalog. Dieser Ordner hält
die **capability-first**-Schicht: welche stabile Capability eine Komponente
implementiert und wie austauschbar das implementierende Tool ist.

Modell: [talos-platform-docs ADR-0021 — Capability-Layer-Modell](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md).
Grundsatz: **Capability = stabile Schnittstelle, Tool = austauschbare
Implementierung.** Ein Tool-Wechsel ist eine Implementierungs-Änderung hinter
derselben Capability, kein Consumer-Rewrite.

## Dateien

- [`capability-index.yaml`](capability-index.yaml) — Registry aller Capabilities,
  die apps-Komponenten bereitstellen, je mit Implementierungen und `swap_class`.

## `swap_class` — Austausch-Kosten

| Klasse | Bedeutung |
|---|---|
| `drop-in` | Gleicher Vertrag, kein Datenumzug |
| `label-move` | Tausch = Label-Verschiebung am Producer-Pod |
| `data-migration` | Tausch erfordert Datenumzug |
| `rewrite-required` | Tool-spezifische CRs müssen neu geschrieben werden |
| `consumer-change` | Consumer muss seine Referenz anpassen |

## capability-first `compatibility.yaml` (erweitert #57)

Das Schema aus #57 bleibt erhalten; capability-first ergänzt es **additiv** —
`requires:` (Versions-Kompatibilität) bleibt unverändert, `provides[]` bekommt
eine `capabilities`-Liste:

```yaml
# sub-layers/<sub-layer>/components/<component>/compatibility.yaml
requires:
  talos-platform-base: ">=v0.4.0 <v1.0.0"   # unverändert (#57): Versions-Range
provides:
  - name: kube-prometheus-stack             # Tool/Chart-Name (unverändert, #57)
    capabilities:                            # NEU: welche Capabilities dieses Tool implementiert
      - {id: metrics-scrape,  swap_class: drop-in}
      - {id: metrics-storage, swap_class: data-migration}
      - {id: metrics-query,   swap_class: drop-in}
      - {id: alert-routing,   swap_class: drop-in}
      - {id: dashboards,      swap_class: label-move}
    apis: []                                 # #57: API-/Chart-Versionen
```

Regeln:

- Jede `id` MUSS in [`capability-index.yaml`](capability-index.yaml) existieren.
- `swap_class` MUSS mit der Implementierung im Index übereinstimmen.
- Ein Tool darf mehrere Capabilities bereitstellen (eine Liste).
- Komponenten ohne passende Capability tragen heute `capabilities: []` mit
  einem `# TODO`-Verweis auf das Folge-Issue, das die Capability definiert
  (Status `proposed` im Index) — Verträge werden nicht erraten.

## Abgrenzung

- Layer A (diese Schicht) ≠ Layer B (PNI Network-Trust, `capability-provider/consumer`-
  Labels + CCNP-Selektoren; Spec in talos-platform-base AGENTS §PNI, Enforcement docs#65).
  Gleicher Begriff „Capability", zwei Achsen — siehe ADR-0021.
- Bis zur base-Phase-3-Ablation bleibt `talos-platform-base/docs/platform-capability-index.yaml`
  die Upstream-Quelle der vollständigen Definitionen; diese Registry ist der
  migrierte apps-Ausschnitt.
