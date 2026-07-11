# Sub-layer `security`

Security and multi-tenancy/governance tooling for the consumer cluster —
workload-level threat detection and enforcement that runs *on* the cluster, plus
namespace/tenant governance, distinct from the secret-management tooling in
`secrets`. The OCI distribution unit is the component; this directory is the
organisational bracket (ADR-0009).

## Components

| Component | sync-wave | Purpose |
|---|---|---|
| [`tetragon`](components/tetragon/) | 0 | eBPF runtime-security observability (Cilium Tetragon). Provides the `runtime-security` capability — kernel-level process/network/LSM event visibility via the agent `DaemonSet`, with the `tetragon-operator` managing the `TracingPolicy` CRDs at runtime. |
| [`capsule-crds`](components/capsule-crds/) | -1 | Strict-B CRDs artifact (ADR-0028) for Capsule: the 11 `capsule.clastix.io` CustomResourceDefinitions only (api-surface-only, no capability). Foundational half of the Capsule multi-tenancy pair; the workload `capsule` (sync-wave 0) ships separately. |

## Notes

- **`runtime-security` capability** (`catalog/capability-index.yaml`): `tetragon`
  is the `active` implementation (`swap_class: rewrite-required` — switching to the
  `considered` alternative `falco` requires rewriting all consumer `TracingPolicy`
  CRs into a different rule schema).
- **Operator-installed CRDs (no strict-B split)**: tetragon keeps
  `crds.installMethod: operator`, so the `TracingPolicy` / `TracingPolicyNamespaced`
  CRDs are installed and upgraded by the `tetragon-operator` at runtime. That is the
  ADR-0028 strict-B "operator-installed CRDs" out-of-scope carve-out, so there is no
  `tetragon-crds` artifact — the component README documents the decision.
- **Privileged host access**: the eBPF agent runs `privileged: true` + `hostNetwork:
  true` (kernel-probe attachment + host process visibility), so its dedicated
  `tetragon` namespace carries `pod-security.kubernetes.io/enforce: privileged`. The
  `tetragon-operator` itself runs fully hardened.
