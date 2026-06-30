# Capability Catalog

`talos-platform-apps` is the central platform catalog. This directory holds
the **capability-first** layer: which stable capability a component
implements and how swappable the implementing tool is.

Model: [talos-platform-docs ADR-0021 — Capability layer model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md).
Principle: **Capability = stable interface, Tool = swappable
implementation.** A tool swap is an implementation change behind the same
capability, not a consumer rewrite.

## Files

- [`capability-index.yaml`](capability-index.yaml) — registry of the
  platform's full Layer-A tool-capability set, each with implementations and
  `swap_class`. Implementations are partly apps components, partly consumer-/
  hardware-deployed; the definition lives centrally here, the tool is deployed
  by the respective owner. Not included (stay in base): substrate capabilities
  (`gitops-engine`, `csr-approval`) and Layer-B network primitives.

## `swap_class` — swap cost

| Class | Meaning |
|---|---|
| `drop-in` | Same contract, no data migration |
| `label-move` | Swap = label move on the producer pod |
| `data-migration` | Swap requires data migration |
| `rewrite-required` | Tool-specific CRs must be rewritten |
| `consumer-change` | Consumer must adapt its reference |

## capability-first `compatibility.yaml` (extended #57)

The schema from #57 is preserved; capability-first extends it **additively** —
`requires:` now contains only **catalog-internal** component deps + capability IDs
(NO `talos-platform-base` line, #71/ADR-0009: apps does not depend on the substrate),
`provides[]` gains a `capabilities` list:

```yaml
# sub-layers/<sub-layer>/components/<component>/compatibility.yaml
requires: {}                                 # NO talos-platform-base line (#71, ADR-0009):
                                             # apps does not depend on the substrate. Only
                                             # catalog-internal component deps + capability IDs here.
provides:
  - name: mimir                             # tool/chart name (#57) — a single component,
                                            # NOT a component stack (ADR-0009 §OCI granularity)
    capabilities:                            # NEW: which capabilities this tool implements
      - {id: metrics-storage, swap_class: data-migration}
      - {id: metrics-query,   swap_class: drop-in}
    version:                                  # apps#226: typed version provenance (replaces apis[])
      sot: app                                # provenance axis: app | chart | crd-schema | none
      app: 2.13.0                             # running app version (the real "what runs")
      chart: 5.5.1                            # Helm chart version (packaging; orthogonal to appVersion)
    api_surface: []                           # exposed CRD/API surface (Kind@version), de-conflicted
```

Rules:

- Every `id` MUST exist in [`capability-index.yaml`](capability-index.yaml).
- `swap_class` MUST match the implementation in the index.
- A tool MAY provide multiple capabilities (a list).
- Components without a matching capability currently carry `capabilities: []`
  with a `# TODO` reference to the follow-up issue that defines the capability
  (status `proposed` in the index) — contracts are not guessed.
- In `requires:`, a fixed catalog component MUST be referenced **concretely**
  as `<sub-layer>/<component>: ">=vX.Y.Z"` — even when it itself provides a
  capability (e.g. `alloy`/`grafana` → `observability/loki|mimir|tempo`,
  **not** the `*-query` capabilities). A **capability ID** in `requires:` is
  reserved for *instanced* services whose **instance the consumer supplies**
  (today `cnpg-postgres`, `redis-managed`, `s3-object`; all `instanced: true`).
  Rule of thumb: a capability ID only where a real, index-listed swap contract
  exists *and* the consumer supplies the instance; a tool-specific contract
  (Grafana-shaped dashboard payload, tool-specific CRs or metric names) is
  referenced **concretely** — otherwise the capability claims a swap-freedom
  that does not exist.
  - **`s3-object` (#427):** the observability stores (`loki`/`mimir`/`tempo`)
    take their S3 endpoint, buckets, and credentials from consumer-owned
    `${S3_*}` env — they never reference the in-cluster `storage-objects/garage`
    Service — so the consumer supplies the object-store instance, exactly the
    `cnpg-postgres` shape. They therefore reference the `s3-object` capability,
    not `storage-objects/garage`. A component that consumes the in-cluster
    Garage workload **directly** still references `storage-objects/garage`
    concretely (the rule above).

### `version:` — version provenance (apps#226)

The former `apis[]` was overloaded (it mixed chart version, image tag, CRD API group,
Crossplane package version, and fictional values) and unenforced — you could not read off
*which version of the actual software* a component deploys. Replaced by a typed
`version:` block with **one** labeled provenance axis per artifact:

- **`sot`** (required) ∈ `{app, chart, crd-schema, none}` — which axis is the "what runs" SOT.
- **`app`** / **`chart`** / **`crd_schema`** — disjoint typed fields (no catch-all):
  running app version / Helm chart version / upstream release of a CRD bundle.
- **`artifacts[]`** — `{image, version}` for multi-image components; headline + primary
  upstream images, **excluding** standard kubernetes-csi sidecars (versioned independently).
- **`api_surface[]`** — the *exposed* CRD/API surface (`Kind@version`), de-conflicted.

Enforcement — **A7 parity gate** (`scripts/lint-version-parity.sh` · `task lint:version` · CI
`version-parity.yml`). Render-checked (hard-fail) is **only the declared SOT axis**, plus
`artifacts[]`:

- `sot: app` → `version.app` must appear in the render (`app.kubernetes.io/version` label, otherwise
  image/package tag).
- `sot: crd-schema` → every `api_surface[]` group/version must exist as a rendered CRD/XRD.
- `artifacts[]` → every `{image, version}` must appear verbatim in the render.

**Deliberately NOT checked (declared-only — do not assume verified):** the `version.chart` value
(even alongside `sot: app`), the `version.crd_schema` **release** value (only the `api_surface`
group/version is render-checked, not this string), and `sot: none`. `sot` is self-declared; the gate
does not prevent a downgrade/deletion of the `version` block (no ratchet). An upstream chart mutation
without a repo diff is caught only by `task ci` / publish, not by this path-filtered PR gate. The job is
(due to the path filter) **not a required check** — see the workflow header.

The `appVersion` in the packaged chart comes from `version.app` (no longer force-stamped onto the OCI
tag; the OCI tag stays `Chart.version`). Track: apps#226 · Capability reference: ADR docs:0029.

## Boundaries

- Layer A (this layer) ≠ Layer B (PNI network trust, `capability-provider/consumer`
  labels + CCNP selectors; spec in talos-platform-base AGENTS §PNI, enforcement docs#65).
  Same term "capability", two axes — see ADR-0021.
- Until the base phase-3 ablation, `talos-platform-base/docs/platform-capability-index.yaml`
  remains the upstream source; thereafter this registry is authoritative for Layer A. base
  keeps only the substrate and network-primitive entries.
