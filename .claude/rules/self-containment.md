---
paths:
  - ".claude/agents/**"
  - ".claude/skills/**"
  - ".claude/hooks/**"
  - ".claude/workflows/**"
  - ".claude/rules/**"
---

# Self-Containment of Repo-Local Primitives

Loaded when you edit a primitive under `.claude/` (the five primitive
directories above — deliberately NOT bare `.claude/**`, which would over-fire on
`settings.json`, transient `reviews/`, and full repo checkouts under
`worktrees/`). The whole point of this repo's
`.claude/` tree is that it is **autark**: any developer who clones the repo gets a
working plan→build→review→verify→document pipeline with **zero dependency on a
personal global Claude config**. This repo ships its primitives in-tree rather
than relying on a `~/.claude/` global setup.

## The rule

Every primitive under `.claude/` (agents, skills, hooks, workflows, rules) stands
alone. A primitive references **nothing** from a developer's personal/global
Claude configuration:

- No reference to `~/.claude` (the home-directory global config).
- No reference to a `claude-config` checkout.
- No bare `rules/<x>.md` or `references/<x>.md` path that resolves to a global
  config file. Repo-local `.claude/rules/<x>.md` references are fine — those ship
  with the repo.

When a primitive needs a convention, it carries it **in-tree**: inline in the
agent/skill body, or in a repo-local `.claude/rules/` file like this one.

## Where discipline lives — main session vs. subagent

- **`.claude/rules/`** (these files) are **main-session editor discipline**. They
  load via `paths:` frontmatter when you read/edit a matching file, reminding you
  of the conventions as you author a primitive.
- **Subagents do NOT load these rules.** A dispatched subagent runs in an isolated
  context and sees only its own agent body + its brief. So any discipline a
  subagent must follow at runtime (injection hardening, judge≠builder boundaries,
  evidence discipline, write-scope) is written **inline into that agent's body**,
  never left only here. Duplication between an agent body and these rules is
  intentional: the rule reminds the editor, the inline copy binds the runtime.

## The deterministic gate

`task check:primitives` is the mechanical enforcer. It fail-closed-checks the
**executable** primitives (`.claude/agents`, `.claude/skills`, `.claude/workflows`,
`.claude/hooks`) for (a) self-containment, (b) A1 no-peer-names, and (c)
verdict-schema consistency. It runs standalone and inside `task ci` (so the GHA
pipeline catches a drift/self-containment break on every PR). Run it before
committing any `.claude/` edit.

These `.claude/rules/` docs are deliberately **outside** the (a) scan: a teaching
doc must be able to name the forbidden patterns above to teach them. Their
self-containment is kept by review. If you ever extend the gate to scan
`.claude/rules`, exclude prohibition-naming or this file self-trips.
