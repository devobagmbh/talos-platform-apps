# Component `lifecycle/crossplane`

Crossplane operator as the composite-resource engine.

Provisions the `pkg.crossplane.io` and `apiextensions.crossplane.io` CRDs that every other component of the `lifecycle` sub-layer (provider CRs, XRDs, compositions) requires as a precondition.

## Contents

- `helm/crossplane.yaml` — Helm chart reference (`crossplane-stable/crossplane@1.18.0`, namespace `crossplane-system`) + default values.

## Sync-wave

First component in the sub-layer (`sync-wave: "0"`). It provisions the CRDs without which `providers`, `compositions`, and everything else would not be installable in the cluster.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/crossplane:vX.Y.Z
```

## Related ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
