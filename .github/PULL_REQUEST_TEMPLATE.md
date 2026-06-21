## What does this PR do?

<!-- REQUIRED: link the issue this PR closes so the Projects board stays
     self-maintaining — a linked issue auto-closes on merge and the board's
     "Pull request merged" / "Item closed" workflows set Status=Done with no
     manual upkeep. If this PR intentionally closes no issue (tooling/docs
     without a ticket), apply the `no-issue` label instead — otherwise the
     pr-issue-link check blocks the PR. -->
Closes #<!-- issue number -->

**Affected sub-layer:** <!-- automation/databases/dns/lifecycle/observability/registry/secrets/storage-objects or "cross-cutting" -->

<!-- Short description — what changes and why? -->

## Validation

- [ ] `task lint` green locally
- [ ] `task render -- <sub-layer>` produces valid YAML
- [ ] `task ci` green locally (full pipeline run)
- [ ] `compatibility.yaml` updated (if the chart version changed)
- [ ] sub-layer `README.md` updated (if components/consumers changed)

## Reviews

- [ ] At least one subagent review attached (see `AGENTS.md` § Multi-Agent-Coordination)
- [ ] Pipeline/signing topics: `provenance-reviewer`
- [ ] `compatibility.yaml` changes: `compatibility-reviewer`
- [ ] Bootstrap/DR impact: `operational-safety-reviewer`
- [ ] Vault/SOPS/RBAC topics: `security-reviewer`

## Commit style

- [ ] Conventional Commits with sub-layer scope (`feat(observability): …`, `fix(dns): …`, `chore(automation): …`)
- [ ] Breaking changes: `BREAKING CHANGE:` footer in the commit + note in the PR body

## Notes

<!-- Optional: test output, screenshots, references to issues/ADRs/runbooks -->
