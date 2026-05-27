# Conftest-Policies

Rego-Policies, die gegen alle gerenderten Sub-Layer-Manifeste laufen. Aufruf via `task scan` lokal (Devbox-Shell) oder als CI-Job im `security-scan.yml`-Workflow.

## Was bedeutet PNI v2?

Mehrere Policies im `platform/`-Verzeichnis setzen das **Platform Network Interface (PNI) v2 Capability-First Contract** durch. PNI v2 stammt aus dem Upstream-Repo [`talos-platform-base`](https://github.com/Nosmoht/talos-platform-base/blob/main/AGENTS.md#platform-network-interface-pni--v2-capability-first-contract) und ist die zentrale Konvention für Producer-/Consumer-Netzwerkbeziehungen im Cluster:

- **Capability statt Tool-Name**: `CiliumClusterwideNetworkPolicy` (CCNP) referenziert eine Capability (`capability-provider.cnpg-postgres`) statt einen Tool-Namen (`app.kubernetes.io/name: cnpg`). Tool-Swap (z. B. Postgres durch CockroachDB) ist dann ein Label-Move auf dem Producer-Pod, kein CCNP-Edit.
- **Reserved Labels namespace-anchored**: `platform.io/provide.<cap>` darf nur auf Namespaces gesetzt werden, die durch Base-RBAC dazu autorisiert sind. `platform.io/capability-provider.<cap>` auf einem Pod ist nur valide, wenn der Namespace die passende `provide.*`-Label trägt.
- **Instanced Capabilities**: Capabilities mit mehreren möglichen Instanzen (`cnpg-postgres`, `vault-secrets`, `redis-managed`, `rabbitmq-managed`, `kafka-managed`, `s3-object`) brauchen einen `.<inst>`-Suffix beim Konsumieren (`consume.cnpg-postgres.atlantis-db`), damit klar ist welche Instanz gemeint ist.

Die drei `platform/`-Policies hier (`capability_selectors`, `instanced_suffix_required`, `network_default_deny_egress`) erzwingen diese Konvention für jeden Sub-Layer-Manifest-Output **bevor** das OCI-Artefakt publiziert wird. Konsumenten-Cluster sehen damit nur PNI-konforme Manifeste.

## Rolle im Policy-Stack

Diese Repo nutzt **Conftest in CI + Kyverno im Cluster** mit getrennten Rollen. Siehe [ADR-0018 Policy-Stack](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md) für die vollständige Begründung.

**Conftest hier**: Pre-OCI-Push-Validation der `rendered/`-Manifeste, bevor sie als signierte OCI-Artefakte publiziert werden. CI-Sekundenfeedback im PR.

**Kyverno später** in Konsumenten-Clustern (Seeder + DHQ): Admission-Webhook-Validation + Kyverno-exklusive Features (cosign-Image-Verify, Auto-Generate, Mutate). Lebt in `sub-layers/secrets/manifests/policies/`.

## Mapping — welche Policy gehört wohin

| Policy | Conftest | Kyverno | Begründung |
|---|---|---|---|
| `no_latest_image_tag` | ✅ | ✅ | Defense-in-Depth |
| `no_inline_secrets` | ✅ | ❌ | Conftest-only: Git-Repo-Inhalt |
| `reserved_labels` | ✅ | ✅ | Defense-in-Depth (PNI v2) |
| `capability_selectors` | ✅ | ❌ | Conftest-only: Sub-Layer-Source-Konvention |
| `gateway_api_only` | ✅ | ❌ | Conftest-only: kein Ingress-Controller im Cluster |
| `required_resource_limits` | ✅ | ✅ | Defense-in-Depth |
| `no_privileged_containers` | ✅ | ✅ | Defense-in-Depth + Allow-Liste |
| `image_verify_platform_oci` | ❌ | ✅ | Kyverno-only: cosign keyless, braucht Sigstore-Backend |
| `auto_default_netpol` | ❌ | ✅ | Kyverno-only: Generate-Policy bei Namespace-Create |
| `imagepullsecret_inject` | ❌ | ✅ | Kyverno-only: Mutate-Policy |

→ **5 Conftest-only, 3 Kyverno-only, 4 Defense-in-Depth.** Quelle für die Defense-in-Depth-Policies bleibt die Conftest-Rego-Datei in diesem Verzeichnis; die Kyverno-Variante in `sub-layers/secrets/manifests/policies/` wird **per Hand konsistent gehalten** (compatibility-reviewer-Subagent prüft Drift).

## Struktur

```text
policies/
├── README.md                       — diese Datei
├── base/                           — Generische Hardening (Defense-in-Depth-Kandidaten)
│   ├── no_latest_image_tag.rego
│   ├── reserved_labels.rego
│   ├── required_resource_limits.rego
│   └── no_privileged_containers.rego
├── apps/                           — Repo-Hygiene (Conftest-only)
│   ├── no_inline_secrets.rego
│   ├── gateway_api_only.rego
│   └── (Helm-Chart-Source-Allow-Liste, README-Pflicht, etc.)
├── platform/                       — Plattform-spezifisch (PNI v2 etc.)
│   └── capability_selectors.rego
└── testdata/                       — Beispiel-Manifeste für conftest verify
    ├── valid/
    └── invalid/
```

## Lokal ausführen

```bash
# Alle Sub-Layer rendern + scannen
task scan

# Nur ein Sub-Layer
task scan -- monitoring

# Direkt mit conftest
conftest test sub-layers/monitoring/rendered/ --policy policies/

# Policy-Selbsttests (testdata/ gegen erwartete Outcomes)
conftest verify --policy policies/
```

## Quellen für Vorlagen

- [Conftest-Docs](https://www.conftest.dev/)
- [OPA-Rego-Reference](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [OPA Gatekeeper Library](https://github.com/open-policy-agent/gatekeeper-library) — Rego-Quellen für Standard-Hardening
- [Upstream-Base-Policies](https://github.com/Nosmoht/talos-platform-base/tree/main/policies) — als Vorlage für PNI-spezifische Policies

## Konventionen

- **Ein Rego-File pro Regel** (`<rule_name>.rego`)
- **Package-Name** spiegelt den Pfad: `package base.no_latest_image_tag`
- **Deny-Statements** klar formuliert: `deny[msg] { ... msg := sprintf("...", [...]) }`
- **Tests** zu jeder Policy: `<rule_name>_test.rego` mit `test_<name>`-Funktionen (`conftest verify`)
- **Severity** über `metadata`-Annotations: `# METADATA\n# title: ...\n# severity: high`

## Status (Bundle-C-Audit 2026-05-26)

Phase-1-Vollausbau gemäß [ADR-0018 § Phase-1-Scope](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md#phase-1-scope) — alle 21 Conftest-Policies + 7 Kyverno-ClusterPolicies werden initial implementiert. Begründung: die Defense-in-Depth-Architektur ist gewollt, „später aktivieren" wäre durch die testdata/-Pflege-Disziplin teurer als sofortige Vollabdeckung.

### Conftest-Policies (21 total)

#### `base/` — generische Hardening

- [ ] `no_latest_image_tag` (MUST) — Helm-Defaults dürfen keine `:latest`-Image-Tags rendern
- [ ] `reserved_labels` (MUST) — Reserved Keys (`platform.io/provide.*`, `capability-provider.*`) nur auf Producer-Resources, namespace-anchored
- [ ] `required_resource_limits` (MUST) — alle Container brauchen `resources.{requests.{cpu,memory},limits.memory}`
- [ ] `no_privileged_containers` (MUST) — `securityContext.privileged: false` außer Allow-Liste
- [ ] `run_as_non_root` (SHOULD) — `securityContext.runAsNonRoot: true` + `runAsUser != 0` außer Cilium/CSI-Allow-Liste
- [ ] `endpointslices_only` (SHOULD) — kein `kind: Endpoints` (deprecated seit K8s 1.33)
- [ ] `storage_class_explicit` (SHOULD) — jede PVC hat `storageClassName` explizit gesetzt
- [ ] `probes_required` (SHOULD) — `livenessProbe` + `readinessProbe` pro Container
- [ ] `no_cluster_admin_binding` (SHOULD) — keine `cluster-admin`-Bindings für Workload-SAs
- [ ] `no_host_path` (SHOULD) — kein `volumeMounts: hostPath:` außer Allow-Liste
- [ ] `namespace_quota` (COULD) — jeder Workload-Namespace hat `ResourceQuota`
- [ ] `limit_range` (COULD) — jeder Workload-Namespace hat `LimitRange` mit Defaults
- [ ] `service_no_externalip` (COULD) — kein `Service.spec.externalIPs`
- [ ] `pod_security_standards` (COULD) — `pod-security.kubernetes.io/enforce: restricted` o. `baseline`
- [ ] `image_digest_pinning` (COULD) — Image-Refs nutzen `@sha256:…`-Digest

#### `apps/` — Repo-Hygiene (Conftest-only)

- [ ] `no_inline_secrets` (MUST) — keine `stringData`/`data` außer SOPS-encrypted oder ESO-Referenz
- [ ] `gateway_api_only` (MUST) — kein `kind: Ingress`, nur `Gateway`/`HTTPRoute`
- [ ] `helm_chart_source_official` (SHOULD) — Helm-Chart-Repo-URL aus Allow-Liste

#### `platform/` — PNI v2

- [ ] `capability_selectors` (MUST) — CCNPs nutzen `capability-provider.<cap>`/`capability-consumer.<cap>`, keine Tool-Name-Selectors
- [ ] `instanced_suffix_required` (SHOULD) — bei `consume.<instanced-cap>` muss `.<inst>`-Suffix gesetzt sein
- [ ] `network_default_deny_egress` (SHOULD) — jeder Workload-Namespace hat Default-Deny-Egress-CCNP

### Kyverno-ClusterPolicies (7 total)

Spiegel der Defense-in-Depth-Policies + Kyverno-only Features. Leben in `sub-layers/secrets/manifests/policies/` (Layer-2-Modul) und werden in Konsumenten-Clustern deployed.

- [ ] `no_latest_image_tag` (Defense-in-Depth-Spiegel)
- [ ] `reserved_labels` / `pni-reserved-labels-enforce` (Defense-in-Depth-Spiegel; teilweise upstream in `talos-platform-base`)
- [ ] `required_resource_limits` (Defense-in-Depth-Spiegel)
- [ ] `no_privileged_containers` (Defense-in-Depth-Spiegel)
- [ ] `image_verify_platform_oci` (Kyverno-only — cosign keyless; [Issue #18](https://github.com/devobagmbh/talos-platform-docs/issues/22))
- [ ] `auto_default_netpol` (Kyverno-only — Generate-Policy bei NS-Create)
- [ ] `imagepullsecret_inject` (Kyverno-only — Mutate-Policy)

### Test-Disziplin

Pro Policy: `<rule_name>_test.rego` (Conftest) bzw. `<policy>-test.yaml` (Kyverno) mit Mindestabdeckung:

- 1 valid-Manifest (passes)
- 1 invalid-Manifest (denies, mit erwarteter Fehler-Message)

Die 4 doppelten Policies haben **gemeinsame `testdata/`** unter `policies/testdata/` — Conftest und Kyverno müssen denselben Test-Korpus bestehen. Drift wird vom `compatibility-reviewer`-Subagent in PRs gefangen.

### Sub-Issue-Aufteilung von #11.8

Vollausbau erfordert Strukturierung. Vorschlag: aus #11.8 werden Sub-Sub-Issues, gebündelt nach Verzeichnis:

- `#11.8.1` — `policies/base/` (15 Policies, ein PR-Bündel mit shared testdata)
- `#11.8.2` — `policies/apps/` (3 Policies, separates Bündel)
- `#11.8.3` — `policies/platform/` (3 Policies, eng mit PNI v2, separates Bündel)
- `#11.8.4` — `sub-layers/secrets/manifests/policies/` (7 Kyverno-ClusterPolicies)

Damit ist Vollausbau in vier Reviewer-tauglichen PRs zerlegbar.
