# Component `storage-objects/garage-operator-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the
[garage-operator](https://github.com/rajsinghtech/garage-operator) — a Kubernetes
operator for [Garage](https://garagehq.deuxfleurs.fr/) distributed S3-compatible
object storage. It ships **only** CustomResourceDefinitions; the operator workload is
a **separate** component, `storage-objects/garage-operator` (sync-wave 1). The two
together form the strict-B pair: CRDs first (this artifact, sync-wave -1), controller
after.

The manifests are extracted **verbatim** from Helm chart `garage-operator` **0.7.3**
(`oci://ghcr.io/rajsinghtech/charts/garage-operator`, appVersion `0.7.3`). Upstream
publishes no CRDs-only chart, so this component is delivered as raw manifests
(`kind: manifests`, `manifests/00-garage-operator-crds.yaml`) — see
§ Regeneration for the exact, re-runnable parity recipe.

## What ships

Exactly six resources, all `kind: CustomResourceDefinition`, all scope `Namespaced`,
all in API group `garage.rajsingh.info`:

| CRD | Kind | shortName |
|---|---|---|
| `garageclusters.garage.rajsingh.info` | `GarageCluster` | `gc` |
| `garagebuckets.garage.rajsingh.info` | `GarageBucket` | `gb` |
| `garagekeys.garage.rajsingh.info` | `GarageKey` | `gk` |
| `garagenodes.garage.rajsingh.info` | `GarageNode` | `gn` |
| `garageadmintokens.garage.rajsingh.info` | `GarageAdminToken` | `gat` |
| `garagereferencegrants.garage.rajsingh.info` | `GarageReferenceGrant` | `grg` |

**No controller ships here** — no Deployment, no Service, no RBAC, no webhook
configurations, no Namespace object. That is the strict-B split: this artifact
establishes the API types, and the workload half runs the reconciler that serves
them. A consumer therefore gets no reconciliation from this artifact alone; a
`GarageCluster` created against these CRDs stays inert until the operator is up.

Every CRD carries the upstream `helm.sh/resource-policy: keep` annotation. It is
deliberately **not** stripped, but it is a **Helm-layer** marker that Argo does
**not** honor for its own prune decisions — the authoritative CR-cascade protection
is `Prune=false` on the consumer's `-crds` Argo Application (§ Consumer wiring).

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage-operator-crds:X.Y.Z
```

The published OCI tag is the **bare SemVer** `X.Y.Z` (`task push` strips the leading
`v`); the **git** tag is the distinct `storage-objects/garage-operator-crds-vX.Y.Z`.

Sync-wave: **`-1`**.

## Ordering

CRD **establishment** is self-contained: the six types register at wave -1 with no
dependency of their own, and single-version reads and writes work immediately. CRD
**conversion** is not self-contained. `garageclusters` declares
`spec.conversion.strategy: Webhook` pointing at service `garage-operator-webhook` in
namespace `garage-operator` (path `/convert`, `conversionReviewVersions: [v1]`), and
its `clientConfig` ships **without** a `caBundle`. So v1beta1 ↔ v1beta2 conversion
works only once **both** of these hold:

1. **cert-manager (wave 0)** has honored the CRD's
   `cert-manager.io/inject-ca-from: garage-operator/garage-operator-webhook-cert`
   annotation and its cainjector has written the CA into the `caBundle` field.
2. The **wave-1 operator** is serving the `/convert` endpoint behind that service.

Until then, an API-server call that needs conversion fails. Consequences a consumer
MUST plan for:

- During initial bootstrap this is benign: no `GarageCluster` CRs exist yet.
- During a **coupled pair bump** (§ Regeneration) there is a short **conversion
  window** between the new CRD schema landing at wave -1 and the new operator
  becoming Ready at wave 1. Reads and writes of `GarageCluster` may fail in that
  window.
- The **blast radius is bounded to `garage.rajsingh.info` CRs**. Nothing else in the
  cluster depends on this conversion webhook, and the other five CRDs declare no
  conversion at all, so they are unaffected.

This runtime dependency is declared as `secrets/cert-manager` under `requires:` in
`compatibility.yaml`. It is deliberately **absent** from
`customization.yaml external_dependencies` — that field expresses sync-ordering
preconditions, and asserting one at wave -1 against a wave-0 component would be both
wrong and unsatisfiable.

## Consumer wiring

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the workload:

1. **`storage-objects/garage-operator-crds`** at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the **authoritative** CR-cascade protection: it stops Argo from
     deleting a CRD — which would cascade-delete every live `GarageCluster`,
     `GarageBucket`, `GarageKey`, `GarageNode`, `GarageAdminToken` and
     `GarageReferenceGrant` CR, destroying the operator's entire declared state —
     when the source no longer contains it. The Helm-layer
     `helm.sh/resource-policy: keep` does not carry this.
   - `ServerSideApply=true` clears the 262 KB client-side-apply annotation limit.
     These CRDs are large (the committed extract is ~28.7k lines), so this is a hard
     requirement here, not a stylistic convention.

   The app MUST additionally carry this `ignoreDifferences` stanza:

   ```yaml
   ignoreDifferences:
     - group: apiextensions.k8s.io
       kind: CustomResourceDefinition
       jqPathExpressions:
         - .spec.conversion.webhook.clientConfig.caBundle
   ```

   Without it the desired state (no `caBundle`) permanently differs from the live
   state (the CA cert-manager injected), so the app never reaches `Synced`, and with
   `selfHeal` enabled Argo **blanks the injected CA** on every reconcile — breaking
   `GarageCluster` conversion in a loop that looks like a cert-manager fault.

2. The workload Application **`storage-objects/garage-operator`** at sync-wave 1,
   which then reconciles against CRDs that already exist.

`CreateNamespace` is not this artifact's concern — cluster-scoped CRDs need no
namespace. Under the sole-claimant rule the `garage-operator` namespace and its Pod
Security Admission label MUST be declared by the workload half, never here; this
artifact ships no `Namespace` object.

## Namespace contract

The `garage-operator` **namespace** and the `garage-operator` **release name** are
part of this artifact's consumer-facing contract, not incidental defaults. Two values
are baked into the shipped CRD bytes:

- the conversion webhook `clientConfig.service` — name `garage-operator-webhook`,
  namespace `garage-operator`;
- the `cert-manager.io/inject-ca-from` annotation value —
  `garage-operator/garage-operator-webhook-cert`.

A consumer **MUST NOT** re-namespace or rename this pair via a Kustomize overlay. A
`namespace:` transformer or a name prefix applied to either half desynchronizes these
references: the API server then resolves the conversion endpoint to a Service that
does not exist, and every `GarageCluster` read **and** write fails — including the
operator's own reconcile loop. This is the one place where ADR-0024's
consumer-overlayable baseline has a hard boundary, and it is not mechanically
enforced by the artifact format; it is enforced by this contract.

## Version topology

A consumer authoring CRs MUST take the served-version topology into account:

- **`garageclusters`** — `v1alpha1` is not served; `v1beta1` is served but
  **`deprecated: true`**; `v1beta2` is served and is the **storage version**. Author
  new `GarageCluster` CRs as `v1beta2`. This is the only CRD with a conversion
  webhook, so v1beta1 CRs remain readable — subject to § Ordering.
- **`garagebuckets`** — `v1alpha1` **and** `v1beta1` are both served, `v1beta1` is
  the storage version, and there is **no conversion configured**
  (`conversion: None`). With no conversion strategy the API server cannot translate
  between the two schemas, so a consumer MUST author `garagebuckets` as **`v1beta1`
  only**. Reading an existing object through the `v1alpha1` endpoint returns the
  stored schema unconverted.
- **`garagekeys`, `garagenodes`, `garageadmintokens`** — `v1alpha1` is not served;
  `v1beta1` is served and is the storage version.
- **`garagereferencegrants`** — `v1beta1` only.

**Expect a future `v1beta3`.** This single chart version already carries three
`GarageCluster` API versions with the middle one deprecated, and four of the six CRDs
still carry a retired `v1alpha1` — an API still actively moving at chart 0.7.x. A
consumer SHOULD treat this component's `api_surface` (`compatibility.yaml`) as the
authoritative served set per version and re-read it on every bump, rather than
assuming continuity of the served set.

## GarageNode coexistence

The catalog also ships `storage-objects/garage-crds`, which carries
`garagenodes.deuxfleurs.fr` — Garage's own integrated peer-discovery CRD (group
`deuxfleurs.fr`, version `v1`, no shortNames). Both artifacts may be installed in the
same cluster:

- **No CRD-name collision.** CRD object names are `<plural>.<group>`, and the groups
  differ (`garage.rajsingh.info` vs `deuxfleurs.fr`), so the two are distinct API
  types with independent schemas.
- **No shortName collision.** The `garage.rajsingh.info` `GarageNode` declares
  shortName `gn`; the `deuxfleurs.fr` one declares none.
- **The plural IS shared.** Both use plural `garagenodes`, so a bare
  `kubectl get garagenodes` is **group-ambiguous** and resolves by the API server's
  discovery ordering rather than by intent. Always use the fully-qualified resource
  name — `kubectl get garagenodes.garage.rajsingh.info` or
  `kubectl get garagenodes.deuxfleurs.fr` — in runbooks, scripts, and RBAC review.

The two also serve different purposes: the `deuxfleurs.fr` CR is written by Garage's
own runtime peer discovery, whereas the `garage.rajsingh.info` one is an
operator-managed node-layout assignment.

## Regeneration

The committed manifests are a **snapshot of chart `garage-operator` 0.7.3**. A
reviewer can reproduce them byte-for-byte:

```sh
# 1. Pull the chart at the pinned version from its OCI repo
helm pull oci://ghcr.io/rajsinghtech/charts/garage-operator --version 0.7.3

# 2. Verify the tarball against the pinned digest
echo "d282cb89ee5d54e5ac7dbf2cd5cfc96e9ad5af31febcbbf7a896afb902937708  garage-operator-0.7.3.tgz" \
  | shasum -a 256 -c -

# 3. Re-run the extraction (yq here is python-yq — the -y flag is MANDATORY,
#    without it the output is JSON)
helm template garage-operator garage-operator-0.7.3.tgz \
  --namespace garage-operator \
  | yq -y 'select(.kind == "CustomResourceDefinition")' > /tmp/regenerated.yaml

# 4. Diff against the committed file — expect no output
diff /tmp/regenerated.yaml \
  sub-layers/storage-objects/components/garage-operator-crds/manifests/00-garage-operator-crds.yaml
```

The extraction runs with **chart defaults** — `crds.install: true`,
`webhooks.enabled: true`, `webhooks.certManager.enabled: true` (the default that emits
the `cert-manager.io/inject-ca-from` annotation) and `crds.keep: true` (the default
that emits `helm.sh/resource-policy: keep`). No `--set` overrides are involved, so the
recipe is fully determined by the chart version.

The chart version is the **drift anchor**, and there is no mechanical drift check. A
chart bump MUST re-vendor this file **and** bump this component — and it MUST happen
**together with** the `storage-objects/garage-operator` workload half's chart pin
(a **coupled bump**: the CRD schemas and the controller that serves them come from
one chart version, and a version skew between the halves is exactly what produces the
conversion failures in § Ordering).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and `task validate:crd-split`'s oracle (`kind: CustomResourceDefinition` count
**> 0** here, **== 0** in the workload artifact). Its workload counterpart is
`storage-objects/garage-operator`.

## Capability

api-surface-only, **no capability** — `capabilities: []`, **permanently**, not as a
deferral. The `garage.rajsingh.info` group is provider-exclusive: these CRDs are the
API surface of one specific operator with no alternative implementation, so there is
no swappable capability to name an id for (precedent: `lifecycle/providers`, likewise
api-surface-only). The swappable S3 object-store capability is provided by the
serving workload, not by a CRD schema.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
