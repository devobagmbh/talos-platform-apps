# Component `security/tetragon`

[Tetragon](https://tetragon.io) — eBPF-based runtime-security observability for the
Devoba platform. Implements the **`runtime-security`** capability (eBPF-based
runtime-security observability; `swap_class: rewrite-required`).

Helm chart `tetragon` from `https://helm.cilium.io`, pinned to **1.7.0**
(appVersion **1.7.0**). This component ships **two workloads**:

- the **agent `DaemonSet` `tetragon`** — the eBPF agent, one pod per node, which
  attaches kernel probes (kprobes, tracepoints, LSM hooks) and emits runtime-security
  events; and
- the **`tetragon-operator` `Deployment`** — which installs and manages the Tetragon
  CRDs at cluster runtime and reconciles `TracingPolicy` CRs.

The default export mode is `stdout`, so events flow to the cluster log pipeline via an
export-stdout sidecar in the agent pod.

## CRD management — operator-installed (no `-crds` split)

This component keeps `crds.installMethod: "operator"` (pinned explicitly in
`helm/tetragon.yaml`), so the rendered workload contains **zero**
`kind: CustomResourceDefinition` resources. The `TracingPolicy` and
`TracingPolicyNamespaced` CRDs are installed and upgraded by the **tetragon-operator**
at cluster runtime via its own controller loop.

That operator-managed-CRD lifecycle is structurally identical to the Crossplane
provider / XRD case, which AGENTS.md § CRD management (strict-B, ADR-0028) names as an
explicit **out-of-scope carve-out**:

> **Out of scope:** operator-installed CRDs (Crossplane providers / XRDs) — handled by
> the existing sync-wave readiness model, not by this convention.

The strict-B `-crds` split therefore does **not** apply, and there is **no**
`security/tetragon-crds` artifact. Forcing `crds.installMethod: "helm"` would render the
CRDs inline and mandate a split; the operator path avoids that, matches upstream
Cilium's intent, and is the reason the pin must not be changed to `helm` without
re-evaluating the split decision.

> Operational note: because the CRDs are operator-installed, a consumer cannot apply a
> `TracingPolicy` / `TracingPolicyNamespaced` CR until the tetragon-operator has started
> and registered the API group. If the operator fails to start (e.g. RBAC
> misconfiguration), those CRDs will not exist.

## Required privileged settings (eBPF) — NOT over-rides

The agent runs with two settings that are **mandatory** for Tetragon's eBPF function
and MUST NOT be removed:

- `tetragon.securityContext.privileged: true` — kernel probe attachment (eBPF program
  load + map access).
- `tetragon.hostNetwork: true` — host-namespace process and network visibility.

These are the upstream Tetragon architecture (chart defaults), **not** a hardening
regression introduced by this catalog component. Removing either breaks the tool's core
runtime-security observability. They are the reason the `tetragon` namespace enforces
the `privileged` Pod Security level (below). The `tetragon-operator` Deployment, by
contrast, runs fully hardened (`runAsNonRoot`, `allowPrivilegeEscalation: false`, drop
`ALL` caps) — only the agent needs host access.

## Namespace & Pod Security

The agent ships its own `tetragon` namespace (`manifests/00-namespace.yaml`) with
`pod-security.kubernetes.io/enforce: privileged` — tetragon is the sole occupant of the
`security` sub-layer (dedicated namespace), so the Namespace object travels with the
artifact and a shipped manifest wins over Argo `managedNamespaceMetadata`. `privileged`
is the only Pod Security enforce level that admits the agent's `privileged: true` +
`hostNetwork: true` pods; `restricted` and `baseline` both reject privileged containers
at admission. This matches the [`storage-block/synology-csi`](../../../storage-block/components/synology-csi/)
precedent — a CSI driver with host access uses `enforce: privileged` for the same
host-access class.

The chart renders **no** Namespace object of its own, so the sole Namespace in the
artifact is the catalog-shipped `manifests/00-namespace.yaml`.

## Freeze-line (ADR-0024)

The **workload** (agent DaemonSet + operator Deployment + RBAC) is the signed,
pre-rendered artifact. The agent is **cluster-agnostic at the freeze line**: its eBPF
instrumentation attaches kernel probes regardless of cluster identity, and it runs
without any consumer-supplied secret, config file, or env — so every `required.*` list
is empty. Two **optional** consumer surfaces exist:

- **Config (shape b)** — `provided_refs.config: tetragon-config`. The consumer may
  override the export filters (`exportAllowList` / `exportDenyList` / `exportFilename`);
  the catalog ships usable stdout defaults, so this is an override, never a prerequisite.
- **Selectors (shape d)** — `provided_selectors` names `TracingPolicy` and
  `TracingPolicyNamespaced`, the consumer-authored policy objects the operator selects
  via the `app.kubernetes.io/managed-by: tetragon` label. The agent observes at the base
  level **without** any policy loaded; consumers layer tracing rules on top.
  `required.selector_crs` is empty — no consumer CR is needed for the agent to run.

## Consumer obligations

- **`TracingPolicy` / `TracingPolicyNamespaced` CRs** (which kprobe/tracepoint/LSM rules
  to load) are **consumer-authored** and live in the consumer cluster repos — never in
  this catalog artifact. The agent deploys and operates without them.
- **`tetragon.clusterName`** ships **empty**; the consumer SHOULD set it (via the config
  shape) to identify the source cluster in the event stream when running more than one
  cluster.
- The consumer cluster's **Pod Security Admission** must allow `privileged` workloads in
  the `tetragon` namespace — the shipped namespace label sets this; the consumer's Argo
  Application MAY keep `CreateNamespace=true` or set it `false` (the shipped manifest is
  authoritative for the PSA label either way).

## Sync-wave

`0` — the agent and operator deploy together; the operator establishes the
`TracingPolicy` CRDs at runtime before any consumer `TracingPolicy` CR is applied.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/security/tetragon:tetragon-vX.Y.Z
```

## Related ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md) — operator-installed CRDs out-of-scope carve-out
