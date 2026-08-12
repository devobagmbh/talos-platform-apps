# Component `storage-objects/garage-operator`

The **strict-B workload artifact** (talos-platform-docs ADR-0028) for the
[garage-operator](https://github.com/rajsinghtech/garage-operator) — a Kubernetes
operator for [Garage](https://garagehq.deuxfleurs.fr/) distributed S3-compatible
object storage. It ships the controller and everything that serves the
`garage.rajsingh.info` API; the CustomResourceDefinitions are the **separate**
component [`storage-objects/garage-operator-crds`](../garage-operator-crds/README.md)
at sync-wave -1. This artifact carries **zero** CRDs.

Helm chart `garage-operator` **0.7.3** (appVersion **0.7.3**, image
`ghcr.io/rajsinghtech/garage-operator:v0.7.3`). The chart is published **OCI-only**
(`oci://ghcr.io/rajsinghtech/charts/garage-operator`), which `task render:one`'s
HTTP `--repo` fallback cannot resolve, so the chart is **vendored** as
`vendor/garage-operator-0.7.3.tgz` and that tarball is the mandatory render source.
The `metadata.repo` field in `helm/garage-operator.yaml` is a source reference, not
a render input.

It implements the **`s3-bucket-provisioning`** capability
(`swap_class: rewrite-required`).

## What ships

| Resource | Name | Note |
|---|---|---|
| `Namespace` | `garage-operator` | `pod-security.kubernetes.io/enforce: restricted` |
| `Deployment` | `garage-operator` | 1 replica, leader election on |
| `ServiceAccount` | `garage-operator` | |
| `ClusterRole` ×3 | `-manager-role`, `-metrics-auth-role`, `-metrics-reader` | see § Security posture |
| `ClusterRoleBinding` ×2 | `-manager-rolebinding`, `-metrics-auth-rolebinding` | |
| `Role` / `RoleBinding` | `-leader-election-role[binding]` | namespace-scoped lease/lock |
| `Service` | `garage-operator-webhook` | port 443 → container port 9443 |
| `Service` | `garage-operator-metrics` | ClusterIP :8443, chart default |
| `Certificate` + `Issuer` | `garage-operator-webhook-cert`, `-selfsigned-issuer` | cert-manager |
| `MutatingWebhookConfiguration` | `garage-operator-mutating` | 5 webhook entries |
| `ValidatingWebhookConfiguration` | `garage-operator-validating` | 8 webhook entries |

Both webhook configurations carry
`cert-manager.io/inject-ca-from: garage-operator/garage-operator-webhook-cert` and
`failurePolicy: Fail`, scoped to `garage.rajsingh.info` resources only.

Deliberately **not** shipped: CRDs (`crds.install: false` — strict-B), the
`ServiceMonitor`, the `PrometheusRule` set, the Grafana dashboard ConfigMap, the
chart's metrics `NetworkPolicy`, and the COSI driver. Rationale per key is inline in
`helm/garage-operator.yaml`.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage-operator:X.Y.Z
```

The published OCI tag is the **bare SemVer** `X.Y.Z` (`task push` strips the leading
`v`); the **git** tag is the distinct `storage-objects/garage-operator-vX.Y.Z`.

Sync-wave: **`1`**.

## Decision record

- **Shape B — operator-owns-workload.** The operator is adopted as the deployment
  mechanism for Garage clusters *and* as the declarative bucket/key provisioning
  path, rather than as a provisioning-only side car next to a chart-deployed Garage.
  This diverges from the lean recorded in the adoption issue (#763), which favoured
  the provisioning-only shape; the maintainer decision of 2026-08-11 selected shape B.
  In-scope here are only the two operator components — consumer-side CRs stay
  consumer-owned.
- **Migration is out of scope.** `storage-objects/garage`, `garage-crds` and
  `garage-buckets` remain in the catalog untouched; migrating them onto
  operator-owned `GarageCluster` objects and retiring them is tracked separately
  (#35). Until then the two deployment paths coexist and a consumer picks one.
- **Webhooks stay ON with cert-manager.** The chart default. The conversion webhook
  is what makes `GarageCluster` `v1beta1` ↔ `v1beta2` readable at all, and the
  admission half backs `nodeLocalPools` and delete protection. Precedent for the
  wave-1 + cert-manager shape: `secrets/vault-config-operator`.
- **Upstream pinned, not mirrored.** See § Supply chain.

## Supply chain

Upstream ships keyless cosign signatures **and** SLSA provenance for both the chart
and the operator image, so the chart is pinned upstream rather than mirrored into the
platform registry (ADR-0026 mirroring deliberately declined; decision thread #763).

The vendored tarball is verifiable offline against its committed sidecar:

```sh
cd sub-layers/storage-objects/components/garage-operator/vendor
shasum -a 256 -c garage-operator-0.7.3.tgz.sha256
```

Provenance of chart and image (network required; expect a cosign signature **and**
an `slsa.dev/provenance/v1` predicate for each):

```sh
cosign verify ghcr.io/rajsinghtech/charts/garage-operator:0.7.3 \
  --certificate-identity-regexp \
    '^https://github.com/rajsinghtech/garage-operator/\.github/workflows/helm\.yml@refs/tags/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify ghcr.io/rajsinghtech/garage-operator:v0.7.3 \
  --certificate-identity-regexp \
    '^https://github.com/rajsinghtech/garage-operator/\.github/workflows/docker\.yml@refs/tags/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Both identity regexps end at `@refs/tags/` on purpose: an `@refs/`-terminated
pattern would also accept a signature produced by a branch build.

Chart digest at pin time:
`sha256:9d2df42772f2ab5d31ce2126795b7ed0b7763ab406b023efe8ff7b666a7c674b`; tarball
sha256 `d282cb89ee5d54e5ac7dbf2cd5cfc96e9ad5af31febcbbf7a896afb902937708`.

Neither `shasum -c` nor `cosign verify` proves that the committed tarball **is** the
layer of the pinned chart artifact. Close that loop by reading the layer digest out
of the OCI manifest and comparing it to the sidecar hash above:

```sh
oras manifest fetch \
  ghcr.io/rajsinghtech/charts/garage-operator@sha256:9d2df42772f2ab5d31ce2126795b7ed0b7763ab406b023efe8ff7b666a7c674b \
  | jq -r '.layers[].digest'
# -> sha256:d282cb89ee5d54e5ac7dbf2cd5cfc96e9ad5af31febcbbf7a896afb902937708
```

Residuals a consumer should know:

- **Bus factor 1, `v0.x`, roughly weekly releases.** The pin is deliberate and a bump
  is a reviewed, **coupled** act with the `-crds` half (both halves must come from
  one chart version). An automated chart-version bump MUST NOT be set to automerge
  for this source. If such a bump drops a served API version, the breaking-change
  contract for that lives in the
  [`garage-operator-crds` README](../garage-operator-crds/README.md).
- **`defaultGarageImage` is outside the image-CVE gate.** It reaches the cluster as
  the controller flag `--default-garage-image=…`, not as a Kubernetes `image:` key,
  so the catalog's publish-time image scan (`task scan:trivy-images-of`, whose
  extraction is `[Ii]mage:`-keyed) never sees it. The operand image is covered where
  it *is* an `image:` key — in `storage-objects/garage` — and on the consumer cluster
  by the live-cluster scanning layer.
- **The operand image is unsigned.** `cosign verify docker.io/dxflrs/garage:v2.3.0`
  returns `no signatures found` even with a wildcard identity and issuer, so there is
  deliberately no verify command for it above. Chart and operator image are signed;
  the Garage image the operator runs is not, and its provenance rests on the digest
  pin alone. Accepted gap.
- **Operator-created workloads are outside the signed freeze-line.** The
  StatefulSets, DaemonSets, Services and PVCs the operator generates from
  `GarageCluster` CRs are produced at runtime; the catalog signs only this controller
  baseline. Accepted consequence of shape B.

## Security posture

This operator holds a broad cluster-scoped grant. Read this section before wiring it
into a cluster; the grants below are verifiable in the rendered
`ClusterRole/garage-operator-manager-role`.

- **Cluster-wide `secrets` `create`/`delete`/`get`/`list`/`patch`/`update`/`watch`.**
  This is the sharpest edge of the artifact. The grant is not namespace-scoped and is
  not restricted by label or name, so the operator's ServiceAccount can read **every
  Secret in the cluster** — including unrelated application credentials, and
  including a token that would let an attacker who compromises the operator pod
  escalate further. The operator needs write access to *some* Secrets because it
  mints S3 credentials into a Secret per `GarageKey` (`spec.secretTemplate`); the
  cluster-wide *read* scope is what upstream's generated RBAC grants on top of that
  need. A consumer that considers this unacceptable can scope the operator down: the
  chart's `watchNamespaces` switch makes it use namespace-scoped `Role`s instead of
  `ClusterRole`s. That is a **consumer overlay decision with a functional cost** —
  namespace-scoped installs cannot use `nodeLocalPools`, because node labelling is
  inherently cluster-scoped — and the catalog ships the cluster-scoped default.
- **`nodes` `get`/`list`/`patch`/`update`/`watch`.** The operator writes
  operator-owned activation labels and HostPath claims onto Node objects to make
  node-local pool membership drain-safe, and reads node labels to resolve
  `spec.zoneFrom.nodeLabel`. Node objects are cluster-scoped and shared, so a faulty
  or compromised operator can label or annotate any node in the cluster.
- **`daemonsets`/`deployments`/`statefulsets` `create`/`delete`/… cluster-wide**, plus
  `pods`, `services`, `persistentvolumeclaims`, `configmaps` and
  `poddisruptionbudgets`. This is what shape B means: the operator creates the actual
  Garage workloads.
- **`nodeLocalPools` is a privilege-escalation path.** A `GarageCluster` whose
  `spec.storage.nodeLocalPools` is set makes the operator create a **DaemonSet whose
  pods mount HostPaths** on every selected node. hostPath is a *Baseline*-forbidden
  Pod Security control, so such a workload is admissible only in a namespace labelled
  `pod-security.kubernetes.io/enforce: privileged` — never in this component's own
  `restricted` namespace. The consequence to plan for: **any principal who can create
  a `GarageCluster` can induce a hostPath DaemonSet through the operator's
  ServiceAccount**, without holding the RBAC to create that DaemonSet themselves. No
  catalog gate can see this — the DaemonSet does not exist at render time. Mitigate on
  the consumer cluster: restrict `create` on `garageclusters.garage.rajsingh.info` to
  trusted principals, and use the consumer-side admission policy layer (ADR-0018
  Kyverno safe-defaults) to fence hostPath workloads.
- **`GarageKey.spec.secretTemplate` is the same escalation shape.** Its `name` field
  chooses the Secret the operator writes the minted S3 credentials into. There is no
  `namespace` field, so the write stays in the CR's own namespace — but the name is
  unconstrained, so **any principal who can create a `GarageKey` in namespace N can
  aim the operator's cluster-wide Secret write at an arbitrary Secret name in N** and
  overwrite an unrelated Secret there, without holding Secret-write RBAC themselves.
  Mitigate the same way: restrict `create` on `garagekeys.garage.rajsingh.info` to
  trusted principals.
- **The manager holds `servicemonitors` cluster-wide regardless of
  `serviceMonitor.enabled: false`.** The `create`/`delete`/`get`/`list`/`patch`/
  `update`/`watch` grant on `monitoring.coreos.com` `servicemonitors` is
  upstream-generated into the manager `ClusterRole` and no chart value removes it, so
  it is present even though this artifact ships no `ServiceMonitor`. Accepted
  residual: the operator can write ServiceMonitors it never creates in practice.
- **The operator pod itself is hardened.** `runAsNonRoot` + `seccompProfile:
  RuntimeDefault` at pod level; `allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]` and `readOnlyRootFilesystem: true` on the container; no
  hostPath, no host namespaces, no host ports. Hence `enforce: restricted` on its
  namespace.
- **The metrics endpoint is authenticated, not network-fenced.** It serves on `:8443`
  behind the chart's `metrics-auth` ClusterRole (`TokenReview` /
  `SubjectAccessReview`). The chart's own `NetworkPolicy` is off in this artifact
  because network policy in this platform is capability-selector-based and
  consumer-composed (PNI v2), not tool-name-keyed.

## Ordering and sync-wave 1

Sync-wave **1**, after `secrets/cert-manager` (wave 0) and after the `-crds` half
(wave -1). Both are ordering preconditions, and both are declared in
`customization.yaml external_dependencies`.

On a first sync the webhook configurations and the Deployment land together, so there
is a **transient window** in which `garage.rajsingh.info` CR writes fail with a
webhook-unavailable error: cert-manager must issue the serving certificate, its
cainjector must write the `caBundle` into both webhook configurations (and into the
`-crds` half's `garageclusters` conversion stanza), and the operator pod must become
Ready. All three are asynchronous. At bootstrap this is benign — no CRs exist yet. It
is only a real outage during a **coupled pair bump**, when CRs already exist; see
§ Failure modes → *CR writes are rejected*.

## Consumer obligations

A consumer MUST:

- **Author the `garage.rajsingh.info` CRs itself.** This artifact ships no
  `GarageCluster`, `GarageBucket`, `GarageKey`, `GarageNode`, `GarageAdminToken` or
  `GarageReferenceGrant` object. CRs are cluster-specific composition and live in the
  consumer repo, in consumer-owned namespaces.
- **Wire two Argo `Application`s**, `-crds` at wave -1 and this one at wave 1, and
  carry an `ignoreDifferences` stanza on **both**. On the `-crds` app it covers
  `.spec.conversion.webhook.clientConfig.caBundle` — exact stanza:
  [`garage-operator-crds` README § Consumer wiring](../garage-operator-crds/README.md).
  On **this** app it covers the two webhook configurations: cert-manager's cainjector
  writes the CA into their `clientConfig.caBundle` as well, while the shipped artifact
  leaves that field empty, so the same failure applies here — `selfHeal` blanks the
  injected CA on every reconcile, and admission for `garage.rajsingh.info` CRs breaks
  in a loop that looks like a cert-manager fault:

  ```yaml
  ignoreDifferences:
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
  ```

- **Not re-namespace or rename the pair.** See § Namespace contract below.
- **Pre-create the bootstrap admin `Secret` and reference it from every
  `GarageCluster`** as `spec.admin.adminTokenSecretRef: {name: <secret>, key: <key>}`.
  The operator needs a bearer token to reach Garage's Admin API and apply the cluster
  layout; a `GarageCluster` without that reference **never leaves `phase: Pending`**,
  with the condition `StorageTopologyReady=False (WaitingForLayoutSync)` and the
  message `Auto-mode storage membership exists, but Garage layout convergence cannot
  be verified: creating Garage Admin API client: admin token not configured on
  cluster`. This is a genuine chicken-and-egg and not an oversight in the CR surface:
  `GarageAdminToken` CRs mint *further* tokens **through that same Admin API**, so the
  first token cannot come from a CR — it MUST be a `Secret` the consumer supplies.
- **Pin `spec.image` per `GarageCluster`.** The catalog sets a
  `defaultGarageImage` (`dxflrs/garage:v2.3.0`) so a CR that omits the image still
  gets a pinned, known version — but that default is a catalog-owned convenience, not
  a consumer contract, and it moves when the catalog moves. A consumer that wants a
  stable Garage version across catalog bumps sets `spec.image` explicitly on every
  `GarageCluster`.
- **Size storage explicitly.** `spec.storage.resources`, the metadata/data volume
  definitions and the `storageClass` are per-cluster decisions the catalog cannot
  make. A `GarageCluster` without deliberate storage sizing is an object store whose
  capacity and durability nobody chose.
- **Back up the PVCs the operator generates.** They are created at runtime from
  `GarageCluster` CRs, so they sit outside the signed artifact and outside git-based
  recovery: re-applying the manifests after a cluster loss re-creates the cluster
  structure with **empty volumes**. Object data and Garage metadata are the consumer's
  backup responsibility, on the consumer's own backup path.
- **Set a PSA level on the namespaces its CRs deploy into.** The operator's own
  namespace is `restricted`; the workload namespaces are consumer-owned, and a CR
  using `nodeLocalPools` requires `enforce: privileged` there (§ Security posture).

A consumer SHOULD additionally restrict who may create `GarageCluster` and
`GarageKey` objects (§ Security posture) and enable the `ServiceMonitor` in its own
overlay when it runs a Prometheus stack.

### Namespace contract

The `garage-operator` **namespace** and the `garage-operator` **release name** are
part of the pair's consumer-facing contract, not incidental defaults: the webhook
`clientConfig.service` values, the `cert-manager.io/inject-ca-from` annotations, and
the `-crds` half's conversion stanza all reference them literally. A `namespace:`
transformer or a name prefix applied to either half desynchronizes those references,
and the blast radius is a **complete `GarageCluster` API outage** — the API server
resolves the conversion endpoint to a Service that does not exist, so reads *and*
writes fail, the operator's own reconcile loop included. Nothing in the artifact
format catches this.

### Teardown ordering

Removing this component is **not** symmetric with installing it, because the webhook
configurations are cluster-scoped and outlive the Deployment. Order matters:

1. Delete the consumer's `garage.rajsingh.info` CRs **while the operator is still
   running**, so it can run its finalizers and clean up the workloads it created.
   Deleting CRs after the operator is gone strands objects on finalizers.
2. Delete the workload `Application` (this component). If pruning is enabled, the
   webhook configurations go with it; if it is not, remove them explicitly:
   `kubectl delete mutatingwebhookconfiguration garage-operator-mutating` and
   `kubectl delete validatingwebhookconfiguration garage-operator-validating`.
3. Delete the `-crds` `Application` last, and only deliberately: it runs with
   `Prune=false`, so the CRDs survive by design, and deleting a CRD cascade-deletes
   every remaining CR of that type.

## Failure modes

### CR writes are rejected: `failed calling webhook … connection refused`

**Fingerprint:** `kubectl apply` of any `garage.rajsingh.info` object fails on the
webhook; **reads** of `GarageBucket`/`GarageKey` still work; unrelated kinds
(ConfigMaps, Deployments) are unaffected.

**Cause:** no Ready operator pod behind `garage-operator-webhook`, with
`failurePolicy: Fail`. Either the first-sync transient (§ Ordering), or the operator
is down, or its namespace/Service was renamed.

**Blast radius:** bounded to `garage.rajsingh.info` CR **writes**. The operator is a
controller, not a proxy — it sits on no S3 request path — so data-plane traffic to
already-running Garage clusters is expected to continue while the operator is down;
only reconciliation stops.

**Recovery:** restore the operator (`kubectl -n garage-operator rollout status
deploy/garage-operator`). If it is permanently gone and the CRs must be edited,
delete the two webhook configurations named in § Teardown ordering — accepting that
admission validation is then off — and re-apply this artifact to restore them.

### `GarageCluster` reads fail too, not just writes

**Fingerprint:** as above, but even `kubectl get garageclusters` fails, and only for
that one kind.

**Cause:** the conversion webhook. `garageclusters` is the only CRD with
`spec.conversion.strategy: Webhook`, so reading a stored object through a
non-storage version requires the operator to serve `/convert`. Missing `caBundle`
(cainjector not done, or `ignoreDifferences` missing) or a dead operator both produce
it.

**Recovery:** confirm the `caBundle` on `garageclusters.garage.rajsingh.info` is
non-empty and that the `-crds` app carries the `ignoreDifferences` stanza; then
restore the operator.

### A `GarageCluster` edit reconciles, but the running pods keep the old config

**Fingerprint:** a changed `GarageCluster` field has no effect. The operator reports
the change as applied and the StatefulSet it generated shows a new `updateRevision`
that differs from `currentRevision`, yet the running pod still serves the previous
configuration and the cluster stays in its old phase.

**Cause:** the StatefulSets the operator generates carry `updateStrategy: type:
OnDelete`. The operator writes a new config ConfigMap and updates the StatefulSet, but
Kubernetes does **not** roll the pods — the pod picks up the new config only when it
is recreated.

**Recovery:** delete the affected pods (`kubectl -n <cr-namespace> delete pod
<garage-pod>`) and let the StatefulSet recreate them at the new revision. Plan for
this: every `GarageCluster` config change is a two-step operation, and a consumer
automating CR edits MUST budget the pod deletion into that automation.

### A coupled bump left the CRD schemas and the controller on different versions

**Fingerprint:** conversion or admission errors persisting after both apps report
`Synced`, right after a chart bump.

**Cause:** only one half of the pair was bumped. The CRD schemas and the controller
that serves them come from a single chart version.

**Recovery:** bring both halves to the same chart version and re-sync. Prevention:
bump both in one coordinated change; never automerge a bot's chart bump for this
source.

## Garage feature limits

The CRs are a control-plane interface over Garage's admin and S3 APIs, so they expose
what Garage itself exposes — no more. The limits below are stated in the shipped CRD
schemas (`storage-objects/garage-operator-crds`) and shape what a consumer can
declare:

- **Lifecycle rules are a strict subset of the AWS S3 lifecycle spec**: only
  `Expiration` (days or date — no `ExpiredObjectDeleteMarker`) and
  `AbortIncompleteMultipartUpload`. Filters support prefix and object-size bounds;
  tag filters and the deprecated rule-level `Prefix` are rejected. Garage's lifecycle
  worker runs **once daily**, so rule evaluation is asynchronous from reconciliation
  and never immediate.
- **Static website hosting exposes only `indexDocument` and `errorDocument`** through
  the admin API. Routing rules and redirect-all need a direct S3
  `PutBucketWebsite` call, outside the CR surface.
- **Bucket quotas are `maxObjects` and `maxSize` only.**
- **Access keys carry bucket-scoped read/write/owner permissions** (optionally an
  `allBuckets` baseline and an expiry); there is no policy-document language and no
  IAM-style role model.
- **At most 255 Kubernetes nodes may be selected across all `nodeLocalPools`
  entries**, and Garage's global layout accepts at most 256 positive-capacity roles
  in total — node-local, PVC, manual, external and federated members share that
  budget, so activation can fail below the node ceiling.

For the authoritative S3 API compatibility matrix, consult the upstream Garage
documentation; this component does not restate it.

## Freeze-line (ADR-0024)

The workload is the signed, pre-rendered baseline; the image digest is the hard
consumer-admission anchor and per-cluster fields (replicas, `nodeSelector`,
tolerations, resources) are consumer-overlayable without a catalog PR. There is **no**
consumer config shape (a), (b), (c) or (d): the component reads no consumer ConfigMap
or Secret and assembles no consumer-labelled CRs — its webhook certificate comes from
cert-manager in-cluster. Two things a consumer MUST NOT overlay: the webhook
`failurePolicy: Fail`, and any occurrence of the `garage-operator` name or namespace
(§ Namespace contract).

## Capability

Implements **`s3-bucket-provisioning`** (`swap_class: rewrite-required`) — the
control-plane counterpart to `s3-object`'s data path: buckets, access keys and
per-bucket permissions as Kubernetes objects, with credentials landing in a Secret.
The interface is tool-specific `garage.rajsingh.info` CRs rather than a standard API,
so the index entry is deliberately **not** `instanced`: a dependent component pins
`storage-objects/garage-operator` concretely and MUST NOT put the capability id in
its `requires:`.

## Related ADRs

- [ADR-0028 — CRD management strategy (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management-strategy.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0018 — Policy stack](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0026 — Central Harbor / NAS block storage](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0026-central-harbor-nas-block-storage.md)
  — mirroring this upstream is deliberately declined (§ Supply chain)
