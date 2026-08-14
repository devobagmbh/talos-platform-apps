---
type: decision
title: "DR-0004 — Sanctioned RBAC-narrowing overlays are documented per component and gated against the render"
description: Record a namespace-scoped RBAC narrowing as a supported consumer overlay in the component README, carry it machine-readably in compatibility.yaml rbac_policy, and pin the grant a narrowing consumer binds against a committed golden via task validate:rbac-narrowing — instead of shipping a second component or trusting documentation alone.
tags: [decision, rbac, security, adr-0024, consumer-overlay, gate, storage-objects]
timestamp: 2026-08-14
sources:
  - catalog/rbac-resource-scope.yaml
  - schemas/compatibility.schema.json
  - sub-layers/storage-objects/components/garage-operator/compatibility.yaml
  - sub-layers/storage-objects/components/garage-operator/rbac-baseline.triples
  - sub-layers/storage-objects/components/garage-operator/README.md
  - schemas/testdata/rbac-narrowing/README.md
  - AGENTS.md
---

# DR-0004 — Sanctioned RBAC-narrowing overlays: documented per component, gated against the render

- **Status:** Accepted
- **Date:** 2026-08-14
- **Issue:** #795
- **Record class:** repo-local decision record (`knowledge/decisions/`), distinct from the platform-wide ADR series in `talos-platform-docs/adr/`.
- **Scope:** how the catalog records that narrowing a component's cluster-wide manager `ClusterRoleBinding` to namespace scope is a **supported** consumer customization, and what CI owes a consumer who takes that option. Changes no artifact bytes and no consumer dependency key.

## Context

`storage-objects/garage-operator` publishes a manager `ClusterRole` with cluster-wide
`secrets` CRUD, write on `nodes`, and create/delete on the workload kinds. Its README
told a consumer that considers this unacceptable to use "the chart's `watchNamespaces`
switch" — a mechanism the consumer **cannot reach**: the artifact is a pre-rendered
Kustomize base, and no consumer runs Helm. The same README enumerated the overlayable
surface as a closed set (replicas, `nodeSelector`, tolerations, resources) while listing
RBAC as frozen — the pre-2026-07-08 reading of ADR-0024, which the calibrated-friction
re-frame abolished (the image digest is the hard anchor; every other baseline field is
consumer-overlayable at risk-calibrated friction, RBAC named explicitly).

So the platform contract already permitted the narrowing. What was missing was (a) an
accurate, reachable statement of *which objects and args* a consumer changes, (b) the
functional cost, and (c) any mechanism keeping (a) and (b) true across chart bumps.

## Decision

Three parts, in ascending order of what they cost to maintain:

1. **Document the sanction in the component README** (`### Namespace-scoped operation`),
   in reference form: the three change surfaces split by *where they live* (two
   `kustomize.patches` entries on the Application; the per-namespace `RoleBinding`s as
   consumer-authored additive objects, which `kustomize.patches` cannot express), the
   cost, and the residual risk that survives the narrowing.
2. **Carry it machine-readably** in `compatibility.yaml` as an optional `rbac_policy`
   block (`class: narrowable|fixed`, `cluster_role`, `baseline`,
   `inert_when_namespaced`), following the `crd-bearing` / `resource_policy` precedent.
   Absence means not-narrowable — the safe default that gates nothing rather than
   asserting something.
3. **Gate the grant** with `task validate:rbac-narrowing` (`task ci`): the rendered
   role, a committed golden of its triples, the declared cost, and the README must all
   agree.

## Why documentation alone was not enough

A narrowing consumer keeps the shipped `ClusterRole` and binds it per namespace **by
name**. Two consequences follow that no amount of README prose prevents:

- an upstream chart bump that adds a rule **widens every narrowed consumer's grant
  silently** — the consumer's own manifests do not change, so nothing surfaces in their
  review either;
- a bump that adds a **cluster-scoped** rule silently falsifies the README's cost
  statement, because that rule is precisely what a `RoleBinding` cannot confer.

Neither is visible in an ordinary render-diff review, and a consumer cannot see either
one at all. A catalog that publishes a sanctioned overlay owes the consumer the
invariant the sanction rests on — hence the golden, which turns any rule-set change
into a reviewed grant change before publish.

## Why not a second component, and why not doc-only

A `garage-operator-namespaced` topology variant would double the build, publish, sign
and CVE surface for a difference of two patches, and the AGENTS.md topology-variant
contract is for mutually-exclusive *deployment topologies of a workload*, not for RBAC
scope. Doc-only was rejected for the reasons above. Two things stay out of reach for
any of the three options and are **not** claimed anywhere: two independently scoped
operator installs in one cluster (blocked by the § Namespace contract, which bakes the
name and namespace into the webhook `clientConfig`), and re-namespacing.

## Why compatibility.yaml plus a component-local golden

`customization.yaml` is `additionalProperties: false` with a fixed required key set and
no field able to carry a sanctioned-overlay declaration, so extending it would have
meant inventing a shape in the schema that the ADR-0024 contract does not have.
`compatibility.yaml` already carries per-component markers that gates key on
(`crd-bearing`, `resource_policy`) and already ships with the artifact. The golden is a
plain triple file **in the component directory**, not a central registry: it is the
component's own accepted grant, it is reviewed with the chart bump that changes it, and
a central file would turn every bump into a shared-file conflict (the failure mode the
release-please manifest already demonstrates).

`catalog/rbac-resource-scope.yaml` is central for the opposite reason: resource scope is
a property of the Kubernetes API, identical for every component, and duplicating it per
component would let two components disagree about whether `nodes` is cluster-scoped.

## When a consumer overlay earns a catalog-gated sanction

Not every overlay does — ADR-0024 makes overlays the norm, and gating each one would
re-introduce the enumerate-what-is-open model the re-frame abolished. The bar used here,
all three:

1. the overlay changes the component's **security posture**, so a consumer decides it
   deliberately and needs the facts to decide;
2. it has a **functional cost** the consumer cannot discover from the artifact;
3. the correctness of the documented cost depends on **upstream-owned content** that
   moves on a bump, so the statement decays silently without a gate.

An overlay that fails (3) — resources, replicas, tolerations — needs documentation, not
a gate.

## Named limits of the gate

- **README parity is presence-only.** The gate asserts that the
  `### Namespace-scoped operation` section names the `ClusterRole` and every resource
  the declaration calls inert. It
  cannot judge an **over**-claim, because the section legitimately names retained
  resources too (the residual-risk paragraph) and prose is not a machine-readable set.
  The match is token-delimited rather than a substring, because a `ClusterRole` name is
  a prefix of the `ClusterRoleBinding` name the same section documents deleting, and a
  resource name (`nodes`) is a substring of a CRD resource in the same role
  (`garagenodes`) — either would report a parity that is not there.
  The section's other claims — the patch mechanics, the escalation residual, the metrics
  statement — are reviewer-judged, not gated.
- **A namespaced widening is caught only because the golden pins the whole role**, not
  by any RBAC-specific reasoning. That is deliberate: the alternative (deriving "which
  widenings matter") is a judgement the gate cannot make.
- **The rendered role is not the effective grant** in every shape. `aggregationRule`,
  `resourceNames`, `nonResourceURLs` and wildcards are rejected as unjudgeable rather
  than approximated — a component using them cannot declare `narrowable` until the
  oracle is extended. Each of the four reports its own discriminator, because two of
  them (`aggregationRule`, `nonResourceURLs`) contribute no triples at all: with a
  shared failure token their check could be deleted without any test noticing, and the
  result would be a silent *accept* of a widened grant rather than a wrong message.
  Cardinality is asserted for the same reason — the render concatenates the Helm output
  with `manifests/*.yaml`, so two documents can carry the declared name, and pinning
  the first would certify a rule set that is not the effective grant.
- **Nothing verifies that a consumer's overlay is correct**, only that the grant it
  binds is the reviewed one. Whether the documented overlay actually works is
  established by hand on the local test cluster (`local/README.md`), never by CI — CI
  renders and publishes the cluster-wide default shape.
- **Fail-closed on an empty run** means removing the last `narrowable` component
  requires removing the task from `task ci` in the same change. Accepted: an
  empty-and-green gate is worse than a loud one.

## Consequences

- Adding `rbac_policy: {class: narrowable}` to a component now obliges it to carry a
  golden, a README section under the fixed heading, and a scope-map entry for every
  resource its role names — a real authoring cost, paid once per narrowable component.
- A chart bump that changes the manager role's rules **fails CI** until the golden is
  re-derived and the delta reviewed as a grant change. This is the intended friction.
- The catalog now has a place to record "this overlay is supported" that a machine can
  read, which is the reusable half of this decision; `garage-operator` is its first
  consumer.
