# Component `secrets/cert-manager`

cert-manager (Helm `jetstack/cert-manager`, chart `v1.20.2`) — the X.509
certificate controller for the Devoba platform (`tls-issuance` capability). This
component ships the controller + webhook + cainjector + the full cert-manager
CRD set (`cert-manager.io` + `acme.cert-manager.io`) **plus its dedicated
`cert-manager` Namespace**. It is cluster-agnostic at the freeze line: nothing
from the consumer is needed to render a valid, signed workload.

Migrated from `talos-platform-base/kubernetes/base/infrastructure/cert-manager/`
into the catalog as an independently versioned OCI artifact (ADR-0009).

## Contents

- `helm/cert-manager.yaml` — cert-manager chart reference + slim default values
  (`crds.enabled: true` brings the CRDs with the controller;
  `global.leaderElection.namespace: kube-system`).
- `manifests/00-namespace.yaml` — the dedicated `cert-manager` Namespace carrying
  the PSA `enforce` label (sole-claimant rule, ADR-0032).

## Namespace & Pod Security

cert-manager occupies the **dedicated** `cert-manager` namespace and is its sole
catalog occupant, so this component ships the `Namespace` object (a shipped
manifest is authoritative over Argo `managedNamespaceMetadata`). The namespace
carries `pod-security.kubernetes.io/enforce: restricted` — every workload the
chart renders (the controller, webhook, and cainjector Deployments, and the
post-install startupapicheck Job) is provably `restricted`-compliant
(pod `runAsNonRoot` + `seccompProfile: RuntimeDefault`; every container
`allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]`).

The catalog ships **only** the `enforce` level plus the
`platform.devoba.de/{sub-layer,component}` labels. Per ADR-0032, the **consumer**
adds, in its Argo overlay:

- `pod-security.kubernetes.io/enforce-version` — pinned to the consumer cluster's
  Kubernetes minor (a cluster property, not a catalog default), and
- any PNI labels (`platform.io/provide.*`, `consume.*`, `network-profile`,
  the `vault-ca-distribution` wiring) — these are consumer-composition concerns.

## Operational notes

### Consumer RBAC — leader-election lease

`global.leaderElection.namespace: kube-system` means the controller's
leader-election `Lease` lives in `kube-system`, not in the `cert-manager`
namespace. A consumer cluster running cert-manager under **namespace-scoped**
RBAC must therefore grant the controller `get`/`create`/`update`/`watch` on
`lease` objects in `kube-system` — or override `global.leaderElection.namespace`
to `cert-manager` in its overlay so the lease stays inside the component's own
namespace.

### Disaster recovery

cert-manager keeps **no persistent state**: it is controller-only — no
PersistentVolume, no StatefulSet. The durable state is the consumer's
`Certificate` / `ClusterIssuer` (and the issued Secret) objects, which are
etcd-backed and recovered through a normal etcd restore. After an etcd restore
to an *earlier* snapshot, orphaned in-flight `CertificateRequest` / `Order`
objects may need manual deletion; cert-manager re-issues them on the next
reconciliation.

## Consumer obligations (out of scope here)

`ClusterIssuer`, `Issuer`, and `Certificate` CRs are the consumer's TLS policy —
authored against the CRDs this component installs, they live in the consumer
cluster repos (Layer 3), never in this catalog component. This component installs
the controller + CRDs; the issuers and certificates that drive them are
consumer-owned.

## Sync-wave

`0` — catalog default. The CRDs ship in this wave so consumer ClusterIssuer /
Certificate CRs (later waves) have their API groups available. A consumer that
needs cert-manager earlier at bootstrap deploys it in an earlier wave from its
own overlay.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/cert-manager:0.1.0
```

OCI registry tag at publish is `0.1.0`; the corresponding git tag is
`secrets/cert-manager-v0.1.0` (kept distinct — registry tag vs. SemVer git tag).

## Related ADRs

- ADR-0024 — Customization Contract v2 (freeze-line)
- ADR-0009 — Platform Layer Model (OCI granularity)
- ADR-0032 — Namespace / PSA ownership model
