# Sub-layer reference

One reference concept per catalog sub-layer (12 total): its purpose, its
components with sync-wave, CRD-split, capabilities, and dependencies. Derived
from each `sub-layers/<sl>/README.md` + the per-component `compatibility.yaml` /
`customization.yaml`. Catalog scale: 12 sub-layers, 62 components.

- [automation](automation.md) - cluster backup (Velero) + dependency automation.
- [compute](compute.md) - VM runtime, GPU scheduling, hardware-feature detection.
- [databases](databases.md) - managed PostgreSQL + Valkey.
- [identity](identity.md) - OIDC broker (Dex).
- [lifecycle](lifecycle.md) - Crossplane + providers + iPXE provisioning.
- [network](network.md) - secondary networking + NTP add-ons.
- [observability](observability.md) - the LGTM-A stack + Prometheus/Grafana operators + Hubble.
- [registry](registry.md) - Harbor OCI registry.
- [secrets](secret-management.md) - External Secrets + cert-manager + Vault operator.
- [security](security.md) - multi-tenancy + runtime security.
- [storage-block](storage-block.md) - block-storage CSI drivers.
- [storage-objects](storage-objects.md) - Garage S3-compatible object store.
