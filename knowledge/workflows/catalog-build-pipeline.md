---
type: workflow
title: Catalog build pipeline
description: The plan -> build -> ship pipeline for catalog components, with judge-builder separation and worktree-isolated parallelism.
tags: [workflow, build, pipeline, judge-builder]
timestamp: 2026-07-22
sources:
  - CLAUDE.md
  - AGENTS.md
  - .claude/skills/build-catalog-component/CONVENTIONS.md
  - .claude/skills/plan-catalog-app/CONVENTIONS.md
  - .claude/skills/ship-catalog-app/SKILL.md
---

# Catalog build pipeline

Authoritative source: `CLAUDE.md` §Skills + Workflows, `AGENTS.md` §Multi-Agent
Coordination, and the `CONVENTIONS.md` inside each skill directory. This concept
orients; the skills own the spec.

The pipeline builds catalog components through a builder -> verifier -> reviewer
chain with the **builder and the verifier in separate contexts** (judge-builder
separation - an agent that builds and verifies its own work is the documented
self-verification failure mode).

## The three orchestrating skills

- `/plan-catalog-app <app>` - plans one app (1-N components) through a converging plan -> review -> revise loop: `catalog-planner` writes the plan, `plan-reviewer` reviews it in parallel as two personas, with a finding ledger and a hard round cap. Output: a finding-free plan under `.work/plan/<app>/`.
- `/build-catalog-component <sub-layer>/<component>` - builds one component through builder -> verifier -> reviewer in separate contexts (fix-loop cap 2); branch + PR, never auto-merge.
- `/ship-catalog-app <app>` - end-to-end orchestrator for the full plan -> approve -> build arc of one app, a thin layer over the two skills above.

## The verify leg

The deterministic gate (`task ci` + `task validate:contract` + chart-ref /
tamper check) runs first; the LLM judge (`catalog-evaluator`) then judges only
the semantics the gate cannot see (freeze-line consistency, capability mapping,
README <-> artifact agreement). `catalog-evaluator` has read + bash only, never
write/edit, and is never the context that built the component.

## Parallelism

The primary parallel path is **independent sessions**: each session builds one
component in its own git worktree (`task worktree:create -- <sub-layer>/<component>`,
which uses a cross-session-safe `mkdir` lock and a branch name as the claim), so
multiple sessions run in parallel on one clone. The `catalog-fleet` workflow is
an optional single-operator mass fan-out over the same chain.

## The specification-driven direction

[DR-0001](../decisions/DR-0001-specification-driven-component-build.md) records
the decision to build each component from a **specification** (standard, schema,
ADR, upstream chart values) with a gate bound to the rendered artifact - demoting
copy-from-neighbor to a format-idiom example only.

## Where the detail lives

- Each skill's `SKILL.md` + `CONVENTIONS.md` under `.claude/skills/`.
- The agent roster and phase table: `AGENTS.md` §Multi-Agent Coordination.
