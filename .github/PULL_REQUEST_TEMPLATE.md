## Was tut dieser PR?

Closes #<!-- Issue-Nummer -->

**Betroffener Sub-Layer:** <!-- automation/databases/dns/lifecycle/monitoring/registry/secrets/storage-objects oder „cross-cutting" -->

<!-- Kurzbeschreibung — was ändert sich und warum? -->

## Validation

- [ ] `task lint` lokal grün
- [ ] `task render -- <sub-layer>` produziert valide YAML
- [ ] `task ci` lokal grün (komplette Pipeline durchgelaufen)
- [ ] `compatibility.yaml` aktualisiert (falls Chart-Version geändert)
- [ ] Sub-Layer-`README.md` aktualisiert (falls Komponenten/Konsumenten sich geändert haben)

## Reviews

- [ ] Mindestens ein Subagent-Review hinterlegt (siehe `AGENTS.md` § Multi-Agent-Coordination)
- [ ] Bei Pipeline-/Signing-Themen: `provenance-reviewer`
- [ ] Bei `compatibility.yaml`-Änderungen: `compatibility-reviewer`
- [ ] Bei Bootstrap-/DR-Auswirkungen: `operational-safety-reviewer`
- [ ] Bei Vault/SOPS/RBAC-Themen: `security-reviewer`

## Commit-Style

- [ ] Conventional Commits mit Sub-Layer-Scope (`feat(monitoring): …`, `fix(dns): …`, `chore(automation): …`)
- [ ] Bei Breaking Changes: `BREAKING CHANGE:`-Footer im Commit + Hinweis im PR-Body

## Hinweise

<!-- Optional: Test-Output, Screenshots, Verweise auf Issues/ADRs/Runbooks -->
