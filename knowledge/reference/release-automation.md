---
type: reference
title: Release automation
description: release-please-managed per-component releases, the tag-triggered publish flow, and the config-parity gate.
tags: [reference, release, release-please, oci-publish]
timestamp: 2026-07-11
sources:
  - AGENTS.md
  - .github/workflows
  - release-please-config.json
  - .release-please-manifest.json
---

# Release automation

Authoritative source: `AGENTS.md` §CI conventions -> Release automation.

Component releases are managed by **release-please** (`release-please.yml`), not
hand-cut tags.

## The flow

1. A `feat` / `fix` commit under `sub-layers/<sl>/components/<c>/` (one component per commit) makes release-please open a per-component release PR (`separate-pull-requests`).
2. Merging that PR cuts the tag `<sub-layer>/<component>-vX.Y.Z`.
3. The tag is created with a **GitHub App installation token** (not the built-in `GITHUB_TOKEN`, whose events do not cascade), so the tag-push triggers `oci-publish.yml`, which renders + packages + pushes + signs + verifies.

Because the publishing workflow is unchanged, the cosign signing identity stays
`oci-publish.yml@refs/tags/...` - the same identity `task verify` and the
consumer-side Kyverno policy check.

## Why the PR title matters

Under squash-only merges the PR title becomes the squash commit subject that
release-please parses. A multi-component PR would collapse into one squash commit
that version-bumps every touched component - hence **one PR per component**,
enforced by the PR-title + single-component gate (see [CI and merge gates](ci-and-merge-gates.md)).

## Sources of truth and parity

- Per-component version SoT: `.release-please-manifest.json`.
- Component list: `release-please-config.json` (stubs carry `initial-version: 0.1.0`).
- `task validate:release-config` (in `task ci`) gates config <-> component-directory parity - a new component absent from the config, or a stale entry, fails the pipeline.

## Manual backfill

A manual tag push still triggers `oci-publish.yml` for backfill/hotfix - push at
most three tags per `git push` (tags beyond the third in a single push raise no
workflow run at all). The adoption cutover point is `bootstrap-sha`; pre-cutover
unreleased changes are published via the manual-backfill path.

## Where the detail lives

- Full release-automation contract, the App-token rationale, and the cutover semantics: `AGENTS.md` §CI conventions -> Release automation.
- The publish workflow: `.github/workflows/oci-publish.yml`.
