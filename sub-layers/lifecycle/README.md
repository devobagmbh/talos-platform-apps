# Sub-layer `lifecycle`

Crossplane + providers + iPXE server for stage-1 child-cluster provisioning.

The sub-layer is an organizational grouping; **OCI distribution is per component** (ADR-0009). Each component has its own Helm-chart-wrapper OCI artifact, its own Argo Application, and its own lifecycle.

## Components

| Component | sync-wave | Content | OCI |
|---|---|---|---|
| [`crossplane`](components/crossplane/) | 0 | Crossplane operator (Helm) — ships CRDs | `oci://.../lifecycle/crossplane:vX.Y.Z` |
| [`ipxe`](components/ipxe/) | 0 | iPXE server stub (namespace + labels, content in issue #28) | `oci://.../lifecycle/ipxe:vX.Y.Z` |
| [`booter`](components/booter/) | 0 | proxyDHCP/PXE responder (`siderolabs/booter`), complements `ipxe` (design-B hybrid, ADR-0005) | `oci://.../lifecycle/booter:vX.Y.Z` |
| [`providers`](components/providers/) | 10 | provider-opentofu + provider-kubernetes + pipeline functions | `oci://.../lifecycle/providers:vX.Y.Z` |
| [`compositions`](components/compositions/) | 20 | `XCluster` XRD + Composition (3-step pipeline) | `oci://.../lifecycle/compositions:vX.Y.Z` |
| [`crossview`](components/crossview/) | 30 | Crossplane visualization dashboard (crossplane-contrib) | `oci://.../lifecycle/crossview:vX.Y.Z` |

Sync-wave follows the CRD bootstrap order: wave 0 creates the Crossplane CRDs, wave 10 the provider CRs (need `pkg.crossplane.io/Provider`), wave 20 the XRD + Composition (need active providers), wave 30 the crossview dashboard (reads the Crossplane CRs).

## Consumed by

- A provisioning control-plane consumer — exclusively. Child-cluster provisioning runs from here.
- Provisioned child clusters — no (they do not provision further clusters for now).

## Render convention

Each component is rendered via `task render:one -- lifecycle/<component>` to `components/<component>/rendered/manifest.yaml`. Then packaged + pushed per component:

```bash
task render:one -- lifecycle/crossplane
task package    -- lifecycle/crossplane 0.1.0
task push       -- lifecycle/crossplane 0.1.0
# or together:
task publish    -- lifecycle/crossplane v0.1.0
```

Sub-layer-level aggregate: `task render -- lifecycle` renders all components of this sub-layer.

Input convention per component:

| Directory | Content |
|---|---|
| `helm/*.yaml` | YAML with `metadata.{chart,repo,version,namespace}` + `values` — or `metadata.inline: true` for custom stubs |
| `manifests/*.yaml` | Raw manifests, concatenated 1:1 |

## Backlog issue

[#12 — Sub-layer `lifecycle/`: Crossplane + iPXE](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+lifecycle)

Upstream: [#11 — write the OpenTofu module `talos-cluster`](https://github.com/devobagmbh/talos-platform-apps/issues/?q=OpenTofu-Modul+talos-cluster) — the module is referenced by the `Workspace` and lives in the consumer repo (`<consumer-repo>/stage-1/modules/talos-cluster/`), not here.

## Related ADRs

- [ADR-0003 — Bootstrap-Staging](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0003-bootstrap-staging.md)
- [ADR-0004 — Cluster-Lifecycle-Tooling (Crossplane + provider-terraform)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0005 — Bare-Metal-PXE-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0005-bare-metal-pxe-strategy.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) (component OCI granularity)
