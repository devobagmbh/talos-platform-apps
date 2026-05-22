# Conftest-Policies

Rego-Policies, die gegen alle gerenderten Sub-Layer-Manifeste laufen. Aufruf via `task scan` lokal (Devbox-Shell) oder als CI-Job im `security-scan.yml`-Workflow.

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

## Status (2026-05-22)

Policies-Verzeichnis ist Skelett — konkrete Rules folgen über Issue [#11.8](https://github.com/devobagmbh/talos-platform-docs/issues/62):

- [ ] `base/no_latest_image_tag` — Helm-Defaults dürfen keine `:latest`-Image-Tags rendern
- [ ] `base/reserved_labels` — Reserved Keys (`platform.io/provide.*`, `capability-provider.*`) nur auf Producer-Resources
- [ ] `base/required_resource_limits` — alle Container brauchen `resources.{requests,limits}`
- [ ] `base/no_privileged_containers` — `securityContext.privileged: false` außer Allow-Liste
- [ ] `apps/no_inline_secrets` — keine `stringData`/`data` außer SOPS-encrypted oder ESO-Referenz
- [ ] `apps/gateway_api_only` — kein `kind: Ingress`
- [ ] `platform/capability_selectors` — CCNPs nutzen Capability-Selectors (PNI v2), nicht Tool-Name-Selectors
- [ ] `testdata/` mit valid+invalid-Beispielen für jede Regel

Die korrespondierenden Kyverno-ClusterPolicies (für die 4 Defense-in-Depth + 3 Kyverno-only) folgen in [#15a (sub-layers/secrets)](https://github.com/devobagmbh/talos-platform-apps/issues?q=secrets) und [#18 (image-verify-platform-oci)](https://github.com/devobagmbh/talos-platform-docs/issues/22).
