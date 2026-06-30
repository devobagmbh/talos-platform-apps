---
paths:
  - "AGENTS.md"
  - ".github/workflows/pr-needs-review.yml"
  - ".github/workflows/status-strip.yml"
  - ".github/workflows/pr-issue-link.yml"
  - ".github/workflows/issue-triage.yml"
  - ".github/workflows/project-sync.yml"
  - ".github/PULL_REQUEST_TEMPLATE.md"
  - ".claude/rules/issue-claim.md"
---

# Issue → PR interface — the canonical reference

The single place that describes how an issue in this repo becomes a merged,
ADR-conform PR: the lifecycle, which `status:` label means what and **who owns each
transition**, the command surface for working an issue, and the gates a PR clears
before it merges. It depends on **no** personal or global Claude configuration — what it
cites is a repo-local file, the repo's own GitHub configuration (labels, branch
protection), or a platform ADR the repo already binds to — and it carries the label
meanings inline so a fresh clone has them here.

**This is a map, not the territory.** The authoritative sources are referenced inline
and own their detail:

- **`.claude/rules/issue-claim.md`** — the collision-handling claim protocol (identity,
  the single-`status:` invariant, confirm-read, ownership, end-transitions). Catalog
  skills claiming an issue always go through it; see its §"Wired callers vs. a known
  gap" for the `catalog-fleet` exception that deliberately does not claim.
- **`.github/workflows/*.yml`** — the GitHub Actions that own the GHA-managed label
  transitions at runtime. This reference points at them per row; it does not restate
  their logic (that would drift). See `## Maintenance`.
- **`AGENTS.md`** — the commit / signing / CI / release / ADR conventions the gates
  enforce.

The in-tree catalog skills (`.claude/skills/ship-catalog-app`, `plan-catalog-app`,
`build-catalog-component`) drive the catalog issues through `issue-claim.md`; this
reference is the umbrella for the whole issue→PR contract, including general
(non-catalog) work, which a human or agent drives manually over the same surface.

## Lifecycle

1. An issue under assessment is at `status: triage` (a triager applies it — on open
   `issue-triage.yml` adds only `area:*` / `needs:triage`). The triager sets `kind:` /
   `priority:` / `risk:` and, once the spec is complete and risk-classified, moves it to
   `status: ready`. A spec that fails the readiness check goes to
   `status: needs-clarification` for author action.
2. An operator **claims** a `ready` issue (`→ in-progress`, assignee set) via the
   collision-handling protocol in `issue-claim.md §Claim`.
3. Work happens on a branch off fresh `origin/main`. The issue stays `in-progress`
   for the **whole PR window** — it is never flipped to `needs-review` (that label
   lives on the PR; flipping the issue stranded it before — `issue-claim.md §End-transition`).
4. A PR opens with a `Closes #<N>` link, is reviewed by the code owner, and clears the
   ADR-conformance gates (`## ADR-conformance gates`).
5. On merge, `Closes #<N>` auto-closes the issue and `status-strip.yml` strips its
   `status:` label. No skill action is needed at close time.

Off-ramps: an issue that cannot progress is **blocked** (`→ status: blocked`, reason in
a comment); one handed back is **released** (`→ status: ready`); resuming re-claims it.
A **reopened** issue returns with **no** `status:` label — `status-strip.yml` fires on
close, not reopen, and nothing re-stamps it — so re-triage it manually
(`→ status: triage`) to put it back in the work queue. (An auto-restamp on `reopened` is
a possible workflow follow-up, out of scope for this reference.)

## Label state machine + ownership

Five of the six `status:` labels are **issue** states — an issue carries exactly one
(`issue-claim.md §Single status: label invariant`). The sixth, `needs-review`, is a
**PR-side** label (GHA-owned), never set on the issue; it is listed for completeness.
The meanings transcribe the labels' own GitHub descriptions (their origin, normalized to
stay self-contained); `triage` and `blocked` have **no** workflow owner — a triager /
maintainer sets them.

| `status:` | meaning | set by | cleared by (→ next) |
|---|---|---|---|
| `triage` | issue being assessed; awaits a triager to set kind/priority/risk and move it to `ready` | applied at/after open — manual, no workflow | triager → `ready` (or → `needs-clarification` if the spec fails readiness) |
| `ready` | spec complete and risk-classified; authorized for agent or human pickup | a triager (moving `triage → ready`); `ship-catalog-app` (stopped-at-plan) | claim (`issue-claim.md §Claim`, removes whatever status is present) |
| `in-progress` | actively worked; the assignee identifies the session; held the whole PR window | claim (`issue-claim.md §Claim`) | block (`→ blocked`) / release (`→ ready`) in-session; `status-strip.yml` on close |
| `needs-clarification` | fails a readiness predicate; author action required | `plan-catalog-app` (plan rejected); a triager when the spec is not ready | re-claim (`→ in-progress`) or re-triage (`→ triage`); `status-strip.yml` on close |
| `blocked` | cannot progress; reason recorded in a comment for later untangling | block — manual, no workflow | re-claim when the blocker clears; `status-strip.yml` on close |
| `needs-review` *(PR-side)* | implementation done; awaiting code-owner review | `pr-needs-review.yml` on the **PR** (open, non-draft, base `main`, review outstanding) | `pr-needs-review.yml` on approval, convert-to-draft, retarget-away-from-`main`, close, or `reviewDecision` null (no CODEOWNER claims the paths — dormant today; live when M2 splits CODEOWNERS); `status-strip.yml` on close |

`issue-triage.yml` adds `area:*` labels on open (fallback `needs:triage`, **not** a
`status:` label); `project-sync.yml` mirrors the issue onto the org Project board. The
board lags and is **read-only for claim decisions** — read the label, never the board
(`issue-claim.md`).

## Command surface

GitHub is the tracker; `gh` is the CLI. Identity resolves once as
`me="$(gh api user --jq .login)"` — use the literal `"$me"` everywhere, never `@me`
(`issue-claim.md §Identity`). The token helper is `gh auth token` (for subprocess auth
only — never print the value). `${N}` is the issue number, `${PR}` the PR number.

| Operation | Command |
|---|---|
| list (find work) | `gh issue list --state open --label "status: ready" --json number,title` |
| read | `gh issue view ${N} --json title,body,labels,state,assignees,comments` |
| comment | `gh issue comment ${N} --body-file -` |
| create | `gh issue create --title "${TITLE}" --body-file -` |
| claim / resume | `.claude/rules/issue-claim.md §Claim` — view → remove whatever `status:` label is present → add `status: in-progress` + assignee → confirm-read. The universal entry from `ready`, `needs-clarification`, **or** `blocked` into `in-progress`; the only claim path that runs the collision filter (best-effort, not a lock — `issue-claim.md`). |
| re-triage | `gh issue view ${N} --json labels`, then `gh issue edit ${N} --add-label "status: triage"` — add `--remove-label "<the status: label present>"` **only if** a `status:` label is present (a reopened issue is label-less: add `triage` alone). Kick a spec back to triage, or re-stamp a reopened issue. |
| block | `gh issue view ${N} --json labels`, then `gh issue edit ${N} --add-label "status: blocked" --remove-label "<the status: label present>" --remove-assignee "$me"`, then `gh issue comment ${N} --body-file -` with the reason. Remove only the label actually present (view first) per the single-`status:` invariant; the `blocked` contract records the reason in a comment; releasing the assignee keeps the foreign-claim guard accurate (`issue-claim.md`). |
| release | `gh issue edit ${N} --add-label "status: ready" --remove-label "status: in-progress" --remove-assignee "$me"`. Valid from `in-progress` only — `view` the labels first to confirm `in-progress` is present, or the `--remove-label` errors mid-sequence on an absent label and strands the issue (`issue-claim.md §Single status: label invariant`). |
| pr-open | `printf 'Closes #%s\n\n<summary>\n' "${N}" \| gh pr create --title "<conventional-commit-style title>" --body-file -`. The `Closes #${N}` link is **mandatory** — `pr-issue-link.yml` blocks a PR that neither links an issue nor carries an exempt label. Pass the body on **stdin**: `--body "…\n…"` emits a literal backslash-n, and `--fill` only copies commit messages (no guaranteed link). |
| pr-status | `gh pr checks ${PR} --required`. Full merge gate also via `gh pr view ${PR} --json mergeStateStatus,reviewDecision`. |
| merge/close | `gh pr merge ${PR} --squash` — `Closes #${N}` auto-closes the issue and `status-strip.yml` strips its labels. Branch protection (code-owner review by `robertschneiderdevoba` + required checks + signed commits / `required_signatures`) gates the merge; the command fails cleanly when the PR is BLOCKED. Never `--admin` (multi-maintainer repo — `--admin` bypasses **both** the CODEOWNERS review gate and the `required_signatures` signing gate). `--delete-branch` is optional and only for a same-repo head, never a fork. |

**`no-issue` is not an alternative to `Closes #${N}` for a claimed issue.** It only
exempts a PR that genuinely closes no issue — ticketless docs/tooling changes
(`pr-issue-link.yml`; the bot marker `autorelease: pending` is the other exemption). A
PR that resolves a claimed issue but carries `no-issue` instead of `Closes #${N}` merges
**without** auto-closing the issue, leaving it stranded at `status: in-progress` with
its assignee. Always link a claimed issue.

## ADR-conformance gates

These gates make a PR "consistent + ADR-conform". Each is owned by an `AGENTS.md`
section or a workflow; this list is the consolidated checklist.

- **`task ci` green** — render + `kubeconform` + conftest (the pre-OCI-push policy gate,
  talos-platform-docs ADR-0018) + `task validate:contract` +
  `task validate:crd-split` (strict-B, ADR-0028) + `task validate:release-config`.
  See `AGENTS.md §CI conventions` and `§ADR-Abdeckung`.
- **Signed Conventional Commit**, single component per commit — `required_signatures`
  branch protection + the lefthook `lint:commit-scope` / `lint:commit-msg` gates.
  See `AGENTS.md §Commits & Pull Requests`.
- **Issue link** — `Closes #${N}`, or the `no-issue` label (ticketless), or
  `autorelease: pending` (release-please bot PRs) — `pr-issue-link.yml`.
- **Review** — at least one in-tree reviewer (`staff-reviewer`, escalating to
  `security-reviewer` / `operational-safety-reviewer`) plus the mandatory CODEOWNERS
  review by `robertschneiderdevoba`. See `AGENTS.md §Multi-Agent Coordination` and
  `.github/PULL_REQUEST_TEMPLATE.md`.

## Maintenance

This reference points at the workflows and `issue-claim.md` rather than copying their
logic, so it stays correct as long as the **pointers** are. There is **no** mechanical
parity gate (the repo keeps this a declaration; `task check:primitives` does not scan
`.claude/rules/`), so the drift defense is twofold: the `paths:` frontmatter loads this
file into editor context whenever an owner file (a workflow, `AGENTS.md`,
`issue-claim.md`) is edited, and the discipline to update the matching row when a label
description, a workflow's clear conditions (e.g. the M2 CODEOWNERS split), or a
transition changes. The reference is a map; the workflows and `issue-claim.md` remain
the territory. A mechanical parity check is a possible future hardening.
