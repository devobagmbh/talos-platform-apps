# Conftest-Policies

Rego-Policies, die gegen alle gerenderten Sub-Layer-Manifeste laufen. Aufruf via `task scan` lokal (Devbox-Shell) oder als CI-Job im `security-scan.yml`-Workflow.

## Struktur

```text
policies/
├── README.md                       — diese Datei
├── base/                           — Konventionen aus AGENTS.md (Hard Constraints)
│   ├── no_latest_image_tag.rego
│   ├── reserved_labels.rego
│   └── required_resource_limits.rego
└── platform/                       — Plattform-spezifisch (PNI v2 etc.)
    ├── capability_selectors.rego
    └── (folgt mit Issue #11.8)
```

## Lokal ausführen

```bash
# alle Sub-Layer rendern + scannen
task scan

# nur ein Sub-Layer
task scan -- monitoring

# direkt mit conftest
conftest test sub-layers/monitoring/rendered/ --policy policies/
```

## Quellen

- [Conftest-Docs](https://www.conftest.dev/)
- [OPA-Rego-Reference](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Upstream-Base-Policies in `talos-platform-base/policies/`](https://github.com/Nosmoht/talos-platform-base/tree/main/policies) — als Vorlage; nicht 1:1 übernommen, weil base manche Talos-spezifischen Policies enthält, die für die Sub-Layer-Welt hier nicht passen.

## Konventionen

- **Ein Rego-File pro Regel** (`<rule_name>.rego`)
- **Package-Name** spiegelt den Pfad: `package base.no_latest_image_tag`
- **Deny-Statements** sind klar formuliert: `deny[msg] { ... msg := sprintf("...", [...]) }`
- **Tests**: zu jeder Policy gehört ein `_test.rego` mit `test_<name>`-Funktionen (`conftest verify`)
- **Severity** über `metadata`-Annotations: `# METADATA\n# title: ...\n# severity: high`

## Status (2026-05-22)

Policies-Verzeichnis ist Skelett — konkrete Rules folgen über Issue [#11.8](https://github.com/devobagmbh/talos-platform-docs/issues/?q=Conftest). Erste Kandidaten:

- [ ] `no_latest_image_tag` — Helm-Defaults dürfen keine `:latest`-Image-Tags rendern
- [ ] `reserved_labels` — Reserved Keys (`platform.io/provide.*`, `capability-provider.*`) nur auf Producer-Resources
- [ ] `required_resource_limits` — alle Container brauchen `resources.limits.{cpu,memory}`
- [ ] `capability_selectors` — CCNPs müssen Capability-Selectors verwenden (PNI v2), nicht Tool-Name-Selectors
