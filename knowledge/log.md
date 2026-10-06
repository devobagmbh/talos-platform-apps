# Bundle Update Log

## 2026-10-05

- `observability/snmp-exporter` added: chart `prometheus-snmp-exporter`, five modules extracted from upstream v0.30.1, SNMPv3 credentials in a consumer Secret mounted as a second `--config.file`, no NetworkPolicy shipped (restricting access is a consumer obligation). Registers the `snmp-device-metrics` capability in `catalog/capability-index.yaml`; that row predates the ADR-0029 shape (no `interface_type` / `independence_test`) and migrates with that port. See [observability](reference/sub-layers/observability.md).

## 2026-09-30

- `observability/smartctl-exporter` added: a per-node disk SMART exporter whose chart hard-codes a privileged root container without a namespace, so `no_privileged_containers` now reads the namespace with `object.get(..., "")` and allow-lists the container under the empty-namespace key. See [observability](reference/sub-layers/observability.md).

## 2026-09-25

- No-shadowing gate for declared env keys: a container `env` entry silently beats `envFrom`, so `task validate:env-keys` (in `task ci`) fails a render that carries a declared env or secret key itself or lacks an optional key's placeholder. [DR-0004](decisions/DR-0004-optional-customization-keys.md) gains §No-shadowing (consumer delivery paths, measured patch forms, per-binary placeholder syntax, two rejected designs) and drops its premise that every key arrives through `envFrom`.

## 2026-09-06

- Stacked-PR gating: the six PR-gating workflows lost their `branches: [main]` filter, so a PR based on another PR's branch is gated like one onto `main`. After a base change, close and reopen the PR: the old check conclusion stays on the head SHA and `commit-lint` does not recompute on `merge_group`. See [CI and merge gates](reference/ci-and-merge-gates.md).

## 2026-08-28

- Optional config-file channel hardened after a cross-model review: `path` must be canonical in both channels, `key` may not start with `..`, `required.env_keys` / `required.secret_keys` reject duplicates, and the negative schema fixtures can no longer pass vacuously. [Component contract](reference/component-contract.md) no longer claims both contract files ship in the OCI artifact (`task package` tars only `kustomization.yaml` and `manifest.yaml`).

## 2026-08-27

- Optional config-file channel ([DR-0005](decisions/DR-0005-optional-config-file-channel.md)): `optional.config_files` is a ConfigMap the artifact ships with working content, which the consumer replaces via `source.kustomize.patches`, never by writing into the signed object. `task validate:contract` enforces rules S3–S7 (channel disjointness, identity uniqueness, path uniqueness, no Secret ref, ref equals `provided_refs.config`); `optional.secret_keys` and `optional.selector_crs` stay unbuilt. DR-0004 now records that DR-0005 extends it.

## 2026-08-19

- `observability/grafana` placeholder removed: Grafana is a consumer-instantiated `Grafana` CR reconciled by `observability/grafana-operator`, whose `-crds` half ships the Grafana CRDs. The `dashboards` capability stays `active` with no catalog artifact, like `alert-routing`. See [observability](reference/sub-layers/observability.md).

## 2026-08-18

- Review-response skill `pr-fix` added as the third PR skill (`pr-gate` reviews, `pr-fix` responds, `pr-enqueue` merges): it triages each finding against the PR head, fixes the survivors one commit per finding in `.claude/worktrees/pr-<N>` and stops before the push. Admissibility is deterministic (`task pr:fix:facts`, `task pr:fix:admit`, bound by `task test:pr-fix-admit`); no unattended loop dispatches it.

## 2026-08-17

- Corrected: `task ci` does not run `validate:contract` (it is the separate required check `validate-contract`), in [CI and merge gates](reference/ci-and-merge-gates.md) and `AGENTS.md`. The [glossary](glossary.md) gained `required` vs `optional`, including that renaming an optional key or changing its default breaks consumers silently.

## 2026-08-16

- `storage-objects/garage-operator` runs namespace-scoped (`watchNamespaces`): no manager `ClusterRole` or `ClusterRoleBinding`, where the chart's cluster-wide default granted Secret read plus workload create everywhere. Costs: no `nodeLocalPools` or `zoneFrom.nodeLabel`, operand namespaces must be granted explicitly, and a CR in an unwatched namespace is silently never reconciled. See [storage-objects](reference/sub-layers/storage-objects.md).
- Optional customization keys: [DR-0004](decisions/DR-0004-optional-customization-keys.md) adds the additive top-level `optional` block (env keys with a baked default) to the customization schema and keeps `required` the must-supply channel. `task validate:contract` enforces channel disjointness and name uniqueness.

## 2026-07-27

- `task local:down` force-destroys the local cluster and prunes orphaned talosctl contexts (`task local:context:prune`: only `talos-platform-apps[-NN]` contexts with loopback-only endpoints); `local:cluster:up` prunes first.

## 2026-07-24

- `catalog/capability-index.yaml` joined the `pr:triage` governance-withhold set, so an edit to the capability contract cannot be auto-approved. Still unchecked: the per-component `swap_class` and capability-id copies in `compatibility.yaml` are not compared with the index. [DR-0003](decisions/DR-0003-topology-variant-contract.md) records the closure of the central-file gap.

## 2026-07-23

- Topology-variant contract: [DR-0003](decisions/DR-0003-topology-variant-contract.md) records `catalog/topology-groups.yaml` (mutual exclusion and either-satisfies for `loki` / `loki-distributed` and `tempo` / `tempo-distributed`), gated by `task validate:topology-groups`; `mimir` stays the legacy exception. The [observability](reference/sub-layers/observability.md) note that the exclusion existed in prose only now points at the contract.

## 2026-07-22

- Build contract: `build-catalog-component` `CONVENTIONS.md` gained § Reading rendered artifacts (artifacts over 500 lines are read in bounded windows after a `^kind:` inventory, unread entries named) and § Render-grounded claims (a claim about rendered output is written only after reading the render or chart template). See [catalog build pipeline](workflows/catalog-build-pipeline.md).

## 2026-07-17

- Merge-queue model corrected in [CI and merge gates](reference/ci-and-merge-gates.md): `main` runs the `merge-queue-main` ruleset (SQUASH, ALLGREEN), so `gh pr merge --squash` enqueues instead of merging, `--delete-branch` is incompatible and `--admin` is blocked by the ruleset.

## 2026-07-16

- `events-collect` capability registered in `catalog/capability-index.yaml` (impl `alloy` active, `otelcol` considered, `consumer-change`) for the planned `observability/alloy-singleton`.

## 2026-07-13

- Self-maintenance: `AGENTS.md` § Knowledge-bundle maintenance and the advisory `task okf:freshness` gate (run by `okf-freshness.yml`) added; the blocking flip is tracked in #541.
- Catalog count corrected to 62 components; `vault-config-operator` sync-wave fixed from 0 to 1 (needs `cert-manager` Healthy first) in [secret management](reference/sub-layers/secret-management.md); `task okf:install` checksum-gates the persisted binary.

## 2026-07-11

- Bundle initialized as an OKF v0.1 orientation layer over the catalog's architecture, contracts, gates and workflows; `docs/decisions/0001` moved verbatim to `decisions/DR-0001` and the `docs/` tree removed; the pinned OKF spec is stored as `SPEC.md`.
- `openknowledge` (pinned) validates the bundle via `task okf:validate`; a link gate hard-fails unresolved or bundle-escaping links, which the CLI alone only warns about.
- The bundle became the primary documentation home ([DR-0002](decisions/DR-0002-knowledge-bundle-as-primary-doc-home.md)), with one reference concept per [sub-layer](reference/sub-layers/index.md).
