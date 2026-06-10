#!/bin/bash
# PreToolUse hook: require review artifacts before commits.
# Tiered validation: staff-reviewer primary artifact + on-demand escalation artifacts.
#
# STATUS: dormant — intentionally NOT bound in .claude/settings.json (no "hooks"
# block). With a single maintainer, fail-closed self-review enforcement would be
# self-sabotage; the hook is reactivated when a second maintainer onboards. Until
# then this script is the contract the review agents emit against, not a live gate.
#
# Review-artifact contract (kept in parity with .claude/agents/* and the live
# verdict schema in .claude/workflows/catalog-fleet.js):
#   .claude/reviews/<change-id>/review.md           — staff-reviewer artifact
#     verdict:       approved | rejected | needs-info
#     reviewer-role: staff-reviewer
#     escalations:   [<domain>, ...]   (non-empty + verdict approved ⇒ domain reviews required)
#   .claude/reviews/<change-id>/review-<domain>.md  — one per escalated domain
#     <domain> is a closed set: security | operational-safety | provenance |
#                               compatibility | architecture
#     NOTE: only `security` and `operational-safety` have a backing reviewer agent
#     today. `provenance` / `compatibility` / `architecture` are reserved for M2
#     onboarding; escalating to one of those denies (no agent can produce its
#     artifact) until the reviewer is restored. staff-reviewer's triage table
#     marks these as M2-deferred so it does not route into that dead end.
#     verdict:       approved | rejected | needs-info
#     reviewer-role: <domain>-reviewer
#
# When bound, intercepts Bash `git commit` and MCP GitHub push tools.
# Fail-closed: any unexpected error causes a deny response.
# Receives JSON on stdin from Claude Code.

set -uo pipefail

INPUT=$(cat)

# ── Helper: deny a commit with a reason ─────────────────────────────────────
deny() {
  local reason="$1"
  # Escape backslashes then double quotes for JSON safety
  reason="${reason//\\/\\\\}"
  reason="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

# Trap unexpected errors and fail closed (deny() is now defined above the trap)
trap 'deny "BLOCKED: Internal hook error — cannot validate review artifacts. Fix .claude/hooks/require-review.sh before committing."' ERR

# Preflight: python3 required for JSON/YAML parsing
if ! command -v python3 &>/dev/null; then
  deny "BLOCKED: python3 not found — cannot parse hook input. Install python3 to enable review enforcement."
fi

# Extract the bash command (for Bash tool calls)
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# Determine if this is a commit-capable action.
IS_COMMIT=false

TOOL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

case "$TOOL_NAME" in
  mcp__github__push_files|mcp__github__create_or_update_file)
    IS_COMMIT=true ;;
esac

if [ "$IS_COMMIT" = false ]; then
  if echo "$COMMAND" | grep -qiE '(^|[^a-z])git[[:space:]]+commit|/git[[:space:]]+commit'; then
    IS_COMMIT=true
  fi
fi

# Not a commit action — allow without checking artifacts
if [ "$IS_COMMIT" = false ]; then
  exit 0
fi

# ── Commit detected: validate review artifacts ──────────────────────────────

# Resolve main repo root — works from both main repo and git worktrees.
# git rev-parse --git-common-dir returns ".git" (relative) in the main worktree
# and an absolute path in linked worktrees.
_GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo ".git")
if [[ "$_GIT_COMMON" = /* ]]; then
  _MAIN_REPO=$(cd "$_GIT_COMMON/.." && pwd)
else
  _MAIN_REPO=$(pwd)
fi
REVIEW_BASE="$_MAIN_REPO/.claude/reviews"

if [ ! -d "$REVIEW_BASE" ]; then
  deny "BLOCKED: No .claude/reviews/ directory found. Create review artifacts before committing. See CLAUDE.md governance section."
fi

# Find review directories (exclude hidden files), sorted lexicographically
REVIEW_DIRS=()
while IFS= read -r d; do REVIEW_DIRS+=("$d"); done \
  < <(find "$REVIEW_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if [ "${#REVIEW_DIRS[@]}" -eq 0 ]; then
  deny "BLOCKED: No review directories in .claude/reviews/. Invoke staff-reviewer first."
fi

# Use the last directory (lexicographically most recent by slug)
REVIEW_DIR="${REVIEW_DIRS[${#REVIEW_DIRS[@]}-1]}"
CHANGE_ID=$(basename "$REVIEW_DIR")

# Helper: extract a YAML frontmatter scalar field value
# Usage: get_yaml_field <file> <field>
get_yaml_field() {
  local file="$1"
  local field="$2"
  awk '/^---$/{c++;next} c==1{print}' "$file" 2>/dev/null \
    | (grep -E "^${field}:" || true) \
    | head -1 \
    | sed "s/^${field}:[[:space:]]*//" \
    | tr -d '[:space:]"'"'"
}

# Helper: extract YAML list items from frontmatter
# Handles inline: field: [a, b] and multiline: field:\n  - a\n  - b
# Prints one item per line; empty output = empty list
get_yaml_list() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PYEOF'
import sys, re

file_path = sys.argv[1]
field = sys.argv[2]

try:
    with open(file_path) as f:
        content = f.read()
except Exception:
    sys.exit(0)

# Extract YAML frontmatter (between first and second ---)
parts = content.split('---')
if len(parts) < 3:
    sys.exit(0)

fm = parts[1]

# Try inline list: field: [a, b, c] or field: []
inline = re.search(rf'^{re.escape(field)}:\s*\[([^\]]*)\]', fm, re.MULTILINE)
if inline:
    raw = inline.group(1).strip()
    if raw:
        for item in raw.split(','):
            item = item.strip().strip('"\'')
            # Strip leading 'type:' prefix (LLM sometimes writes '- type: value')
            item = re.sub(r'^type:\s*', '', item)
            if item:
                print(item)
    sys.exit(0)

# Try multiline list:
# field:
#   - item1
#   - item2
ml = re.search(rf'^{re.escape(field)}:\s*\n((?:[ \t]+-[ \t]+\S.*\n?)+)', fm, re.MULTILINE)
if ml:
    for line in ml.group(1).splitlines():
        m = re.match(r'[ \t]+-[ \t]+(\S.*)', line)
        if m:
            item = m.group(1).strip().strip('"\'')
            # Strip leading 'type:' prefix (LLM sometimes writes '- type: value')
            item = re.sub(r'^type:\s*', '', item)
            if item:
                print(item)
PYEOF
}

# ── Validate primary review.md ───────────────────────────────────────────────

PRIMARY="$REVIEW_DIR/review.md"

if [ ! -f "$PRIMARY" ]; then
  deny "BLOCKED: Missing review.md for change '${CHANGE_ID}'. Invoke staff-reviewer to produce it."
fi

PRIMARY_VERDICT=$(get_yaml_field "$PRIMARY" "verdict")

if [ -z "$PRIMARY_VERDICT" ]; then
  deny "BLOCKED: review.md for '${CHANGE_ID}' has no parseable 'verdict' field. Check YAML frontmatter."
fi

# Escalations are read independently of the verdict: a non-empty escalations list
# on an approved primary review means domain reviews must accompany it. Each
# escalated domain <d> requires review-<d>.md with verdict: approved. One level of
# chained escalation (a domain review that itself escalates) is supported.
# Escalation domains are a closed set. Enforce membership BEFORE constructing any
# review-<domain>.md path: an out-of-set value (typo, or a path-traversal-shaped
# string like '../../x') is a contract violation, not a missing-artifact case.
assert_domain() {
  case "$1" in
    security|operational-safety|provenance|compatibility|architecture) return 0 ;;
    *) deny "BLOCKED: '${1}' is not a valid escalation domain for '${CHANGE_ID}' (closed set: security|operational-safety|provenance|compatibility|architecture)." ;;
  esac
}

validate_escalations() {
  local list="$1"
  while IFS= read -r esc_type; do
    [ -z "$esc_type" ] && continue
    assert_domain "$esc_type"

    ESC_FILE="$REVIEW_DIR/review-${esc_type}.md"
    if [ ! -f "$ESC_FILE" ]; then
      deny "BLOCKED: Escalation artifact 'review-${esc_type}.md' missing for change '${CHANGE_ID}'. Invoke the ${esc_type} reviewer."
    fi

    ESC_VERDICT=$(get_yaml_field "$ESC_FILE" "verdict")
    if [ -z "$ESC_VERDICT" ]; then
      deny "BLOCKED: review-${esc_type}.md for '${CHANGE_ID}' has no parseable 'verdict' field."
    fi

    case "$ESC_VERDICT" in
      approved)
        # Domain review clean. If it chained a further escalation, each nested
        # domain review must itself be approved (one level deep).
        NESTED_ESCS=$(get_yaml_list "$ESC_FILE" "escalations")
        while IFS= read -r nested_type; do
          [ -z "$nested_type" ] && continue
          assert_domain "$nested_type"
          NESTED_FILE="$REVIEW_DIR/review-${nested_type}.md"
          if [ ! -f "$NESTED_FILE" ]; then
            deny "BLOCKED: Nested escalation artifact 'review-${nested_type}.md' missing for change '${CHANGE_ID}'."
          fi
          NESTED_VERDICT=$(get_yaml_field "$NESTED_FILE" "verdict")
          if [ "$NESTED_VERDICT" != "approved" ]; then
            deny "BLOCKED: review-${nested_type}.md for '${CHANGE_ID}' has verdict '${NESTED_VERDICT:-<missing>}', not 'approved'."
          fi
        done <<< "$NESTED_ESCS"
        ;;

      rejected|needs-info)
        deny "BLOCKED: review-${esc_type}.md for '${CHANGE_ID}' has verdict '${ESC_VERDICT}'. Resolve before committing."
        ;;

      *)
        deny "BLOCKED: review-${esc_type}.md for '${CHANGE_ID}' has unknown verdict '${ESC_VERDICT}'."
        ;;
    esac
  done <<< "$list"
}

case "$PRIMARY_VERDICT" in
  approved)
    # Own scope clean. If domains were escalated, each needs an approved domain review.
    ESCALATIONS=$(get_yaml_list "$PRIMARY" "escalations")
    if [ -n "$ESCALATIONS" ]; then
      validate_escalations "$ESCALATIONS"
    fi
    ;;

  rejected)
    deny "BLOCKED: review.md for '${CHANGE_ID}' has verdict 'rejected'. Resolve all findings before committing."
    ;;

  needs-info)
    deny "BLOCKED: review.md for '${CHANGE_ID}' has verdict 'needs-info'. Supply the missing evidence / clarification before committing."
    ;;

  *)
    deny "BLOCKED: review.md for '${CHANGE_ID}' has unknown verdict '${PRIMARY_VERDICT}'. Valid values: approved, rejected, needs-info."
    ;;
esac

# ── Role separation check ────────────────────────────────────────────────────
# No artifact in the review directory may be authored by senior-implementer

for review_file in "$REVIEW_DIR"/*.md; do
  [ -f "$review_file" ] || continue
  ROLE=$(get_yaml_field "$review_file" "reviewer-role")
  if [ "$ROLE" = "senior-implementer" ]; then
    artifact=$(basename "$review_file")
    deny "BLOCKED: ${artifact} was produced by 'senior-implementer'. Role separation violated — implementer cannot self-review."
  fi
done

# All checks passed — allow the commit
exit 0
