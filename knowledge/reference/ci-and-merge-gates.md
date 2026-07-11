---
type: reference
title: CI and merge gates
description: The CI conventions, the required status checks, and the branch-protection contract that gate a merge to main.
tags: [reference, ci, merge-gate, branch-protection]
timestamp: 2026-07-11
sources:
  - AGENTS.md
  - Taskfile.yml
  - .github/workflows
---

# CI and merge gates

Authoritative source: `AGENTS.md` §CI conventions and §Branch protection & merge
gates. The **live GitHub branch-protection config is authoritative**; the
`AGENTS.md` section describes the configured contract, and if the two diverge the
live config wins.

## Three binding CI conventions

1. **Devbox cache active** - every GHA job uses the devbox install action with `enable-cache: true`; tool versions come from `devbox.json` / `devbox.lock`. Never `actions/setup-*`.
2. **Locally reproducible** - every task runs on the workstation exactly as in CI; `task ci` reproduces the pipeline locally. No GHA-specific code in tasks.
3. **Pipeline = task caller** - workflow steps only call `task <name>`. A closed set of API-orchestration workflows (label/board automation, release-please, the security-scan escalation step) is the documented carve-out.

The `openknowledge` bundle gate (`task okf:validate`) is a fourth, narrower
carve-out to convention 1: `openknowledge` is not a Nix/devbox package, so its
CLI is installed in CI from a pinned release asset. See
[Catalog build pipeline](../workflows/catalog-build-pipeline.md) and `AGENTS.md`.

## Required status checks

All must be green, with `strict` on (the PR branch must be up to date with main):

- `ci` - `task ci` (render + kubeconform + conftest + `validate:contract` + `validate:crd-split` + `validate:release-config`).
- `validate-contract` - component-contract schema conformance.
- `require-issue-link` - the PR links an issue or carries the `no-issue` label.
- `gitleaks (secret-scan)` - no secret leaks in the PR's changed range.
- `commit-lint` (pending) - Conventional PR title + single-component scope; becomes required once armed.

## Non-status-check merge gates

- **Signed commits** (`required_signatures`) - an unsigned commit makes the PR BLOCKED.
- **CODEOWNERS review** - at least one approving review from the code owner.
- **Conversation resolution** - all review threads resolved.

## Merge method - squash-only

Merge-commit and rebase merges are disabled; `gh pr merge <N> --squash` is the
only path. The squashed commit takes its **subject from the PR title** and its
**body from the PR description**, so the PR title must be a valid Conventional
Commit with a single sub-layer/component scope - that title is what release-please
path-maps to a component (see [Release automation](release-automation.md)).

Never `gh pr merge --admin`: the fix for a BLOCKED PR is always to satisfy the
gate, not to bypass it.

## Where the detail lives

- The full required-check table and branch-integrity rules: `AGENTS.md` §Branch protection & merge gates.
- The task definitions: `Taskfile.yml`.
- The GHA workflows: `.github/workflows/`.
