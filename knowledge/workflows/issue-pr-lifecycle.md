---
type: workflow
title: Issue and PR lifecycle
description: How an issue becomes a merged PR - the status state machine, the claim protocol, and the ADR-conformance gates.
tags: [workflow, issue, pr, lifecycle]
timestamp: 2026-07-23
sources:
  - AGENTS.md
  - .claude/rules/issue-interface.md
  - .claude/rules/issue-claim.md
---

# Issue and PR lifecycle

Authoritative source: `.claude/rules/issue-interface.md` (the canonical
reference) and `.claude/rules/issue-claim.md` (the collision-safe claim
protocol). `AGENTS.md` §Issue & PR Lifecycle points at both. This concept only
orients - read the rules before working an issue or opening a PR.

## The interface

The end-to-end issue -> PR interface is consolidated in
`.claude/rules/issue-interface.md`: how an issue becomes a merged, ADR-conform
PR, the `status:` label state machine and who owns each transition, the `gh`
command surface, and the ADR-conformance gates.

## Who drives the labels

The GitHub Actions under `.github/workflows/` own the GHA-managed `status:`
label transitions at runtime (a closed set of API-orchestration workflows -
`issue-triage.yml`, `project-sync.yml`, `pr-needs-review.yml`, `status-strip.yml`,
`pr-issue-link.yml`). A linked PR auto-closes its issue on merge, so the
Projects board's `Status=Done` needs no manual upkeep; a PR closing no issue must
carry the `no-issue` label.

## Claiming an issue

The collision-safe claim protocol lives in `.claude/rules/issue-claim.md` - the
mechanism that lets multiple sessions/agents work the backlog without racing on
the same issue.

## Merge gates

A PR merges only when every branch-protection gate is green - see
[CI and merge gates](../reference/ci-and-merge-gates.md) for the required checks,
the signed-commit requirement, CODEOWNERS review, and the squash-only merge
method.

## Where the detail lives

- The canonical interface + state machine: `.claude/rules/issue-interface.md`.
- The claim protocol: `.claude/rules/issue-claim.md`.
- The lifecycle summary: `AGENTS.md` §Issue & PR Lifecycle.
