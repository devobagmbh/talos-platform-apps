#!/bin/bash
# SubagentStart hook: injects the YAML comment-admission rule into the subagent that
# writes component YAML (bound in .claude/settings.json with a matcher on its agent type).
#
# Single source: the block between the comment-rule markers in DOCUMENTATION.md. Nothing
# of the rule is restated here.
#
# Fail-open: a missing file, a missing, duplicated or reversed marker, or a block over
# 120 lines produces no output and exit 0 — a hook never blocks a subagent from starting.
# `task test:comment-rule-hook` is the loud half. COMMENT_RULE_DOC redirects the source
# file for that test.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || exit 0
doc="${COMMENT_RULE_DOC:-$root/DOCUMENTATION.md}"
[ -r "$doc" ] || exit 0

block="$(awk '
  /^<!-- comment-rule:begin -->$/ { b++; if (b == 1) bl = NR }
  /^<!-- comment-rule:end -->$/   { e++; if (e == 1) el = NR }
  { line[NR] = $0 }
  END { if (b == 1 && e == 1 && bl < el) for (i = bl + 1; i < el; i++) print line[i] }
' "$doc")" || exit 0
[ -n "$block" ] || exit 0
[ "$(printf '%s\n' "$block" | wc -l)" -le 120 ] || exit 0

body="$(printf '%s\n' "$block" | tr -d '\r' | tr '\t' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
  | awk 'BEGIN { ORS = "" } { print (NR > 1 ? "\\n" : "") $0 }')"

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"YAML comment rule for the files you write (source: DOCUMENTATION.md, section Manifest and config-file inline comments):\\n%s"}}\n' "$body"
exit 0
