# Capability-Katalog

`talos-platform-apps` ist der zentrale Plattform-Katalog. Dieser Ordner hält
die **capability-first**-Schicht: welche stabile Capability eine Komponente
implementiert und wie austauschbar das implementierende Tool ist.

Modell: [talos-platform-docs ADR-0021 — Capability-Layer-Modell](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md).
Grundsatz: **Capability = stabile Schnittstelle, Tool = austauschbare
Implementierung.** Ein Tool-Wechsel ist eine Implementierungs-Änderung hinter
derselben Capability, kein Consumer-Rewrite.

## Dateien

- [`capability-index.yaml`](capability-index.yaml) — Registry des vollständigen
  Layer-A-Tool-Capability-Satzes der Plattform, je mit Implementierungen und
  `swap_class`. Implementierungen sind teils apps-Komponenten, teils consumer-/
  hardware-deployt; die Definition lebt zentral hier, das Tool deployt der
  jeweilige Owner. Nicht enthalten (bleiben base): Substrat-Capabilities
  (`gitops-engine`, `csr-approval`) und Layer-B-network-primitives.

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
`requires:` enthält nur noch **katalog-interne** Komponenten-Deps + Capability-IDs
(KEINE `talos-platform-base`-Zeile, #71/ADR-0009: apps hängt nicht vom Substrat ab),
`provides[]` bekommt eine `capabilities`-Liste:

```yaml
# sub-layers/<sub-layer>/components/<component>/compatibility.yaml
requires: {}                                 # KEINE talos-platform-base-Zeile (#71, ADR-0009):
                                             # apps hängt nicht vom Substrat ab. Hier stehen nur
                                             # katalog-interne Komponenten-Deps + Capability-IDs.
provides:
  - name: mimir                             # tool/chart name (#57) — a single component,
                                            # NOT a component stack (ADR-0009 §OCI-Granularität)
    capabilities:                            # NEU: welche Capabilities dieses Tool implementiert
      - {id: metrics-storage, swap_class: data-migration}
      - {id: metrics-query,   swap_class: drop-in}
    version:                                  # apps#226: typisierte Versions-Provenienz (ersetzt apis[])
      sot: app                                # Provenienz-Achse: app | chart | crd-schema | none
      app: 2.13.0                             # laufende App-Version (das echte „was läuft")
      chart: 5.5.1                            # Helm-Chart-Version (Packaging; orthogonal zu appVersion)
    api_surface: []                           # exponierte CRD/API-Oberfläche (Kind@version), de-konfliert
```

Regeln:

- Jede `id` MUSS in [`capability-index.yaml`](capability-index.yaml) existieren.
- `swap_class` MUSS mit der Implementierung im Index übereinstimmen.
- Ein Tool darf mehrere Capabilities bereitstellen (eine Liste).
- Komponenten ohne passende Capability tragen heute `capabilities: []` mit
  einem `# TODO`-Verweis auf das Folge-Issue, das die Capability definiert
  (Status `proposed` im Index) — Verträge werden nicht erraten.

### `version:` — Versions-Provenienz (apps#226)

Der frühere `apis[]` war überladen (mischte Chart-Version, Image-Tag, CRD-API-Group,
Crossplane-Package-Version und Fiktives) und unenforced — man konnte nicht ablesen, *welche
Version der echten Software* eine Komponente deployt. Ersetzt durch einen typisierten
`version:`-Block mit **einer** gelabelten Provenienz-Achse pro Artefakt:

- **`sot`** (Pflicht) ∈ `{app, chart, crd-schema, none}` — welche Achse die „was läuft"-SOT ist.
- **`app`** / **`chart`** / **`crd_schema`** — disjunkte typisierte Felder (kein Catch-all):
  laufende App-Version / Helm-Chart-Version / Upstream-Release eines CRD-Bundles.
- **`artifacts[]`** — `{image, version}` für Multi-Image-Komponenten; Headline + primäre
  Upstream-Images, **ohne** Standard-kubernetes-csi-Sidecars (eigenständig versioniert).
- **`api_surface[]`** — die *exponierte* CRD/API-Oberfläche (`Kind@version`), de-konfliert.

Enforcement — **A7-Parity-Gate** (`scripts/lint-version-parity.sh` · `task lint:version` · CI
`version-parity.yml`). Render-geprüft (hard-fail) wird **nur die deklarierte SOT-Achse**, plus
`artifacts[]`:

- `sot: app` → `version.app` muss im Render erscheinen (`app.kubernetes.io/version`-Label, sonst
  Image-/Package-Tag).
- `sot: crd-schema` → jede `api_surface[]`-Group/Version muss als gerenderte CRD/XRD existieren.
- `artifacts[]` → jedes `{image, version}` muss exakt im Render vorkommen.

**Bewusst NICHT geprüft (declared-only — nicht als verifiziert annehmen):** der `version.chart`-Wert
(auch neben `sot: app`), der `version.crd_schema`-**Release**-Wert (nur die `api_surface`-Group/Version
wird gerendert-geprüft, nicht dieser String), sowie `sot: none`. `sot` ist selbst-deklariert; das Gate
verhindert kein Downgrade/Löschen des `version`-Blocks (kein Ratchet). Upstream-Chart-Mutation ohne
Repo-Diff fängt erst `task ci` / Publish, nicht dieses path-gefilterte PR-Gate. Der Job ist (path-filter-bedingt)
**kein required check** — siehe Workflow-Header.

Der `appVersion` im gepackten Chart stammt aus `version.app` (nicht mehr force-gestampt auf den OCI-Tag;
der OCI-Tag bleibt `Chart.version`). Track: apps#226 · Capability-Bezug: ADR docs:0029.

## Abgrenzung

- Layer A (diese Schicht) ≠ Layer B (PNI Network-Trust, `capability-provider/consumer`-
  Labels + CCNP-Selektoren; Spec in talos-platform-base AGENTS §PNI, Enforcement docs#65).
  Gleicher Begriff „Capability", zwei Achsen — siehe ADR-0021.
- Bis zur base-Phase-3-Ablation bleibt `talos-platform-base/docs/platform-capability-index.yaml`
  die Upstream-Quelle; danach ist diese Registry autoritativ für Layer A. base
  behält nur die Substrat- und network-primitive-Einträge.
