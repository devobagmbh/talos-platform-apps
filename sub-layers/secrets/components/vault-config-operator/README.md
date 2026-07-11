# vault-config-operator

Kubernetes operator ([redhat-cop/vault-config-operator](https://github.com/redhat-cop/vault-config-operator))
that configures a HashiCorp Vault instance declaratively through `redhatcop.redhat.io`
custom resources (`Policy`, `SecretEngineMount`, `VaultSecret`,
`KubernetesAuthEngineRole`, …). This is the **workload half** of the strict-B
CRD split (ADR-0028): the controller Deployment, RBAC, webhook configurations,
and cert-manager `Certificate`/`Issuer` resources — zero CRDs. The CRDs ship in
the separate [`vault-config-operator-crds`](../vault-config-operator-crds/README.md)
artifact.

It implements the `secret-config-declarative` capability
(swap class `rewrite-required`: moving to a different tool means rewriting every
consumer CR against that tool's schema).

## What ships

- Namespace `vault-config-operator` with `pod-security.kubernetes.io/enforce: restricted`
  (dedicated namespace — this component is its sole catalog occupant).
- Helm chart `vault-config-operator` `v0.8.49` from
  `https://redhat-cop.github.io/vault-config-operator/` (the chart's dedicated
  index): manager Deployment, ServiceAccount, RBAC, Services,
  `MutatingWebhookConfiguration` / `ValidatingWebhookConfiguration`, and
  cert-manager `Certificate` (×2) + `Issuer`.
- Webhook TLS is catalog-managed: `enableCertManager: true` renders two
  cert-manager `Certificate` resources and one `Issuer`, so the webhook serving
  certificate and CA injection need no consumer-supplied secret. With the chart
  default (`false`), both webhooks carry `failurePolicy: Fail` with no CA bundle
  — admission would reject every request.
- Hardened baseline: PSA-restricted security contexts pinned for the manager
  container; explicit resource requests/limits (conftest
  `base.required_resource_limits`). The `kube_rbac_proxy.*` values are inactive
  with `enableMonitoring: false` — the chart renders no sidecar container.

### Accepted upstream-chart residuals

- The chart unconditionally renders the kube-rbac-proxy `ClusterRole` /
  `ClusterRoleBinding` (`authentication.k8s.io` tokenreviews +
  `authorization.k8s.io` subjectaccessreviews `create`) bound to the
  controller-manager ServiceAccount even though the sidecar is disabled —
  accepted risk; upstream chart behavior with no values knob.
- The controller-manager metrics Service renders as a dead endpoint
  (`targetPort: https` with no matching container port) — harmless, upstream
  behavior.
- The `vault-config-operator-metrics-reader` ClusterRole (`nonResourceURLs:
  /metrics`, `get`) renders **unbound** — no ClusterRoleBinding references it;
  it is provided for an external Prometheus to bind.
- The `vault-config-operator-prometheus-k8s` namespace-scoped Role +
  RoleBinding grant the `prometheus-k8s` ServiceAccount in
  `openshift-monitoring` read access — OpenShift monitoring RBAC, dead on
  vanilla Kubernetes (neither the namespace nor the ServiceAccount exists).
- Both Services carry the `service.alpha.openshift.io/serving-cert-secret-name`
  annotation — OpenShift-only, ignored on vanilla Kubernetes.

## OCI path

```text
ghcr.io/devobagmbh/talos-platform-apps/secrets/vault-config-operator:<tag>
```

Git tag pattern: `secrets/vault-config-operator-vX.Y.Z` (the OCI registry tag is
the bare `X.Y.Z`).

## Sync-wave

**1.** Ordering rationale:

- `secrets/vault-config-operator-crds` (wave -1) establishes the
  `redhatcop.redhat.io` CRDs first.
- `secrets/cert-manager` (wave 0) must be fully **Healthy** — not merely applied
  — before this component: its controller and cainjector issue the webhook
  serving certificate and inject the CA bundle into the webhook configurations.
  Wave 1 gives that guarantee; at wave 0 the `Certificate`/`Issuer` resources
  would race a not-yet-running cert-manager.
- Expected cascade: if cert-manager is degraded at wave 0, this component fails
  to reach Healthy at wave 1 (no serving certificate → webhook TLS missing).
  That is correct behavior, not a defect.
- First-sync window: during the initial sync, `redhatcop.redhat.io` CR
  operations fail transiently (~30–60 s) while cert-manager issues the webhook
  serving certificate and cainjector injects the CA bundle. This is
  self-healing, not a cert-manager degradation.
- Recovery/diagnostics: if the `vault-config-operator-webhook-service-cert`
  Secret is lost, cert-manager (wave 0) MUST be healthy — it re-issues the
  certificate automatically. Verify webhook readiness via
  `kubectl get mutatingwebhookconfiguration vault-config-operator-mutating-webhook-configuration -o jsonpath='{.webhooks[0].clientConfig.caBundle}'`
  (non-empty once injected).

## Consumer obligations

- Wire **two** Argo `Application`s (ADR-0028): the `-crds` artifact at wave -1
  with `Prune=false`, then this workload at wave 1.
- Provide `secrets/cert-manager` (or an equivalent cert-manager installation
  providing `cert-manager.io/v1`) at an earlier wave.
- Author the operator's CRs (`Policy`, `SecretEngineMount`, `VaultSecret`, …)
  in the consumer repo — they are not part of the signed artifact. Each CR
  names its own Vault connection, so a reachable Vault instance (in-cluster or
  remote) is a runtime prerequisite for reconciliation, not a sync-order
  dependency of this component.
- Monitoring is off in the catalog artifact (`enableMonitoring: false`); a
  consumer with a Prometheus stack enables it per-cluster.
- Teardown: remove the component by deleting its Argo `Application` with
  pruning enabled. `kubectl delete namespace vault-config-operator` alone
  orphans the **cluster-scoped** webhook configurations, which then reject
  every `redhatcop.redhat.io` CR operation cluster-wide (`failurePolicy: Fail`
  with no backing service). Recovery from that state: delete the orphaned
  webhook configurations by name —
  `kubectl delete mutatingwebhookconfiguration vault-config-operator-mutating-webhook-configuration`
  and
  `kubectl delete validatingwebhookconfiguration vault-config-operator-validating-webhook-configuration`.
  The `-crds` Application is removed separately — its CRDs are `Prune=false`
  by design (ADR-0028).

The component is cluster-agnostic: `customization.yaml` declares no required
consumer config (all `required.*` lists empty) — the consumer interaction
surface is entirely CR-based.

## Related ADRs

- ADR-0009 — platform layer model / per-component OCI distribution
- ADR-0018 — policy stack (conftest pre-push gate, PSA levels)
- ADR-0024 — v2 freeze-line customization contract
- ADR-0028 — strict-B CRD split (`-crds` sibling artifact)
