# Conftest Policies

Rego policies that run against all rendered sub-layer manifests. Invoked via `task scan` locally (Devbox shell) or as a CI job in the `security-scan.yml` workflow.

## What does PNI v2 mean?

Several policies in the `platform/` directory enforce the **Platform Network Interface (PNI) v2 capability-first contract**. PNI v2 originates in the upstream repo [`talos-platform-base`](https://github.com/Nosmoht/talos-platform-base/blob/main/AGENTS.md#platform-network-interface-pni--v2-capability-first-contract) and is the central convention for producer/consumer network relationships in the cluster:

- **Capability instead of tool name**: a `CiliumClusterwideNetworkPolicy` (CCNP) references a capability (`capability-provider.cnpg-postgres`) instead of a tool name (`app.kubernetes.io/name: cnpg`). Swapping the tool (e.g. Postgres for CockroachDB) is then a label move on the producer pod, not a CCNP edit.
- **Reserved labels namespace-anchored**: `platform.io/provide.<cap>` may only be set on namespaces authorized for it by base RBAC. `platform.io/capability-provider.<cap>` on a pod is valid only if the namespace carries the matching `provide.*` label.
- **Instanced capabilities**: capabilities with multiple possible instances (`cnpg-postgres`, `vault-secrets`, `redis-managed`, `rabbitmq-managed`, `kafka-managed`, `s3-object`) require a `.<inst>` suffix when consumed (`consume.cnpg-postgres.atlantis-db`) so it is clear which instance is meant.

The three `platform/` policies here (`capability_selectors`, `instanced_suffix_required`, `network_default_deny_egress`) enforce this convention for every sub-layer manifest output **before** the OCI artifact is published. Consumer clusters therefore see only PNI-conformant manifests.

## Role in the policy stack

This repo uses **Conftest in CI + Kyverno in the cluster** with separate roles. See [ADR-0018 Policy Stack](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md) for the full rationale.

**Conftest here**: pre-OCI-push validation of the `rendered/` manifests before they are published as signed OCI artifacts. Seconds-fast feedback in the PR.

**Kyverno later** in consumer clusters (Seeder + Office-Lab): admission-webhook validation + Kyverno-exclusive features (cosign image verification, auto-generate, mutate). Lives in `sub-layers/secrets/manifests/policies/`.

## Mapping — which policy goes where

`Assignment (target)` = the planned Conftest/Kyverno split of the Phase-1 full build-out; `Impl.` = the current on-disk state (`✅` = `.rego` exists, `➖` = not yet created).

| Policy | Assignment (target) | Impl. | Rationale |
|---|---|---|---|
| `no_latest_image_tag` | both | ✅ | Defense-in-depth |
| `pod_security_standards` | Conftest | ✅ | PSA namespace-label enforcement, Conftest-only |
| `pod_security_conformance` | Conftest | ✅ | PSA conformance check (`task scan:psa-conformance`), Conftest-only |
| `no_inline_secrets` | Conftest | ✅ | Conftest-only: Git repo content |
| `reserved_labels` | both | ➖ | Defense-in-depth (PNI v2) |
| `capability_selectors` | Conftest | ➖ | Conftest-only: sub-layer source convention |
| `gateway_api_only` | Conftest | ➖ | Conftest-only: no ingress controller in the cluster |
| `required_resource_limits` | both | ✅ | Defense-in-depth |
| `no_privileged_containers` | both | ✅ | Defense-in-depth + allow-list |
| `image_verify_platform_oci` | Kyverno | ➖ | Kyverno-only: cosign keyless, needs a Sigstore backend |
| `auto_default_netpol` | Kyverno | ➖ | Kyverno-only: generate policy on namespace create |
| `imagepullsecret_inject` | Kyverno | ➖ | Kyverno-only: mutate policy |

→ **6 implemented (Conftest), 6 planned.** The source of truth for the defense-in-depth policies remains the Conftest Rego file in this directory; the Kyverno variant in `sub-layers/secrets/manifests/policies/` is **kept consistent by hand** (the `compatibility-reviewer` subagent checks for drift).

## Structure

```text
policies/
├── README.md                       — this file
├── base/                           — generic hardening (defense-in-depth candidates)
│   ├── no_latest_image_tag.rego
│   ├── no_latest_image_tag_test.rego
│   ├── no_privileged_containers.rego
│   ├── no_privileged_containers_test.rego
│   ├── pod_security_standards.rego
│   ├── pod_security_standards_test.rego
│   ├── required_resource_limits.rego
│   └── required_resource_limits_test.rego
├── apps/                           — repo hygiene (Conftest-only)
│   ├── no_inline_secrets.rego
│   └── no_inline_secrets_test.rego
└── conformance/                    — PSA conformance check
    ├── pod_security_conformance.rego
    └── pod_security_conformance_test.rego
```

## Run locally

```bash
# Render + scan all sub-layers
task scan

# A single sub-layer only
task scan -- observability

# Directly with conftest
conftest test sub-layers/observability/rendered/ --policy policies/

# Policy self-tests (testdata/ against expected outcomes)
conftest verify --policy policies/
```

## Template sources

- [Conftest docs](https://www.conftest.dev/)
- [OPA Rego reference](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [OPA Gatekeeper Library](https://github.com/open-policy-agent/gatekeeper-library) — Rego sources for standard hardening
- [Upstream base policies](https://github.com/Nosmoht/talos-platform-base/tree/main/policies) — template for PNI-specific policies

## Conventions

- **One Rego file per rule** (`<rule_name>.rego`)
- **Package name** mirrors the path: `package base.no_latest_image_tag`
- **Deny statements** stated clearly: `deny[msg] { ... msg := sprintf("...", [...]) }`
- **Tests** for every policy: `<rule_name>_test.rego` with `test_<name>` functions (`conftest verify`)
- **Severity** via `metadata` annotations: `# METADATA\n# title: ...\n# severity: high`

## Status (issue #236, 2026-06-24)

Phase-1 build-out per [ADR-0018 § Phase-1 Scope](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md#phase-1-scope) — 21 Conftest policies + 7 Kyverno ClusterPolicies planned; the checkboxes below show implemented vs deferred. Issue #236 implemented the three hardening policies (`required_resource_limits`, `no_privileged_containers`, `no_inline_secrets`) and refactored `no_latest_image_tag` to recurse (depth-1) into `Object.spec.forProvider.manifest`.

### Grandfather / allow-list debt register

The three newly enforcing policies carry transitional grandfather sets or a permanent allow-list derived from the current rendered catalog (`task render` probe, issue #236). They are marked FROZEN — a diff growing a set is a blocking reviewer finding; rename-in-place to track an upstream chart rename is allowed.

| Policy | Type | Size | Retirement tracker |
|---|---|---|---|
| `required_resource_limits` | grandfather `(namespace, kind, name)` | 25 workloads | [#349](https://github.com/devobagmbh/talos-platform-apps/issues/349) |
| `no_privileged_containers` | permanent allow-list `(namespace, kind, workload, container)` | 13 containers | per-entry reviewer/ADR sign-off |
| `no_inline_secrets` | grandfather `(namespace, name)` | 6 secrets | [#350](https://github.com/devobagmbh/talos-platform-apps/issues/350) |

The subsections below (`base/`, `apps/`, `platform/`) structure the **planned** full build-out. The current on-disk state is shown by the `## Structure` tree above.

### Conftest Policies (21 total)

#### `base/` — generic hardening

- [x] `no_latest_image_tag` (MUST) — Helm defaults must not render `:latest` image tags; recurses (depth-1) into `Object.spec.forProvider.manifest` (issue #236)
- [ ] `reserved_labels` (MUST) — reserved keys (`platform.io/provide.*`, `capability-provider.*`) only on producer resources, namespace-anchored
- [x] `required_resource_limits` (MUST) — every container needs `resources.{requests.{cpu,memory},limits.memory}`; **enforcing for new components — 25 existing workloads grandfathered pending [#349](https://github.com/devobagmbh/talos-platform-apps/issues/349)**
- [x] `no_privileged_containers` (MUST) — `securityContext.privileged: true` forbidden except a permanent container-level allow-list (13 containers); infrastructure-level necessity documented per entry
- [ ] `run_as_non_root` (SHOULD) — `securityContext.runAsNonRoot: true` + `runAsUser != 0` except for the Cilium/CSI allow-list
- [ ] `endpointslices_only` (SHOULD) — no `kind: Endpoints` (deprecated since K8s 1.33)
- [ ] `storage_class_explicit` (SHOULD) — every PVC sets `storageClassName` explicitly
- [ ] `probes_required` (SHOULD) — `livenessProbe` + `readinessProbe` per container
- [ ] `no_cluster_admin_binding` (SHOULD) — no `cluster-admin` bindings for workload SAs
- [ ] `no_host_path` (SHOULD) — no `volumeMounts: hostPath:` except for an allow-list
- [ ] `namespace_quota` (COULD) — every workload namespace has a `ResourceQuota`
- [ ] `limit_range` (COULD) — every workload namespace has a `LimitRange` with defaults
- [ ] `service_no_externalip` (COULD) — no `Service.spec.externalIPs`
- [x] `pod_security_standards` (COULD) — every declared namespace carries `pod-security.kubernetes.io/enforce` (`privileged`|`baseline`|`restricted`); the strictest level the workload satisfies
- [ ] `image_digest_pinning` (COULD) — image refs use an `@sha256:…` digest

#### `apps/` — repo hygiene (Conftest-only)

- [x] `no_inline_secrets` (MUST) — no non-empty `data`/`stringData` in rendered `Secret` manifests; **enforcing for new components — 6 harbor/crossview secrets grandfathered pending [#350](https://github.com/devobagmbh/talos-platform-apps/issues/350)**
- [ ] `gateway_api_only` (MUST) — no `kind: Ingress`, only `Gateway`/`HTTPRoute`
- [ ] `helm_chart_source_official` (SHOULD) — Helm chart repo URL from an allow-list

#### `platform/` — PNI v2

- [ ] `capability_selectors` (MUST) — CCNPs use `capability-provider.<cap>`/`capability-consumer.<cap>`, no tool-name selectors
- [ ] `instanced_suffix_required` (SHOULD) — a `consume.<instanced-cap>` must set the `.<inst>` suffix
- [ ] `network_default_deny_egress` (SHOULD) — every workload namespace has a default-deny-egress CCNP

#### `conformance/` — PSA conformance

- [x] `pod_security_conformance` (MUST) — rendered workloads conform to the declared `enforce` level (`task scan:psa-conformance`)

### Kyverno ClusterPolicies (7 total)

Mirror of the defense-in-depth policies + Kyverno-only features. They live in `sub-layers/secrets/manifests/policies/` (a layer-2 module) and are deployed in consumer clusters.

- [ ] `no_latest_image_tag` (defense-in-depth mirror)
- [ ] `reserved_labels` / `pni-reserved-labels-enforce` (defense-in-depth mirror; partly upstream in `talos-platform-base`)
- [ ] `required_resource_limits` (defense-in-depth mirror)
- [ ] `no_privileged_containers` (defense-in-depth mirror)
- [ ] `image_verify_platform_oci` (Kyverno-only — cosign keyless; [Issue #18](https://github.com/devobagmbh/talos-platform-docs/issues/22))
- [ ] `auto_default_netpol` (Kyverno-only — generate policy on NS create)
- [ ] `imagepullsecret_inject` (Kyverno-only — mutate policy)

### Test discipline

Per policy: `<rule_name>_test.rego` (Conftest) or `<policy>-test.yaml` (Kyverno) with minimum coverage:

- 1 valid manifest (passes)
- 1 invalid manifest (denies, with the expected error message)

The 4 duplicated policies have **shared `testdata/`** under `policies/testdata/` — Conftest and Kyverno must pass the same test corpus. Drift is caught by the `compatibility-reviewer` subagent in PRs.

### Sub-issue breakdown of #11.8

Full build-out requires structuring. Proposal: #11.8 becomes sub-sub-issues, bundled by directory:

- `#11.8.1` — `policies/base/` (15 policies, one PR bundle with shared testdata)
- `#11.8.2` — `policies/apps/` (3 policies, separate bundle)
- `#11.8.3` — `policies/platform/` (3 policies, tightly coupled to PNI v2, separate bundle)
- `#11.8.4` — `sub-layers/secrets/manifests/policies/` (7 Kyverno ClusterPolicies)

This decomposes the full build-out into four reviewer-friendly PRs.
