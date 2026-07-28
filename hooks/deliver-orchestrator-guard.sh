#!/bin/sh
# PreToolUse guard for the /deliver flow.
#
# Enforces the boundary documented in ~/.claude/agents/deliver-orchestrator.md:
# a `claude --agent deliver-orchestrator` main thread writes only the plan file,
# never repo source. Every source edit is a Develop subagent turn (step 03).
#
# Inert outside a constrained launch: plain sessions carry no `agent_type` key in
# the PreToolUse payload, so this exits 0 after a single jq read.
#
# Exit 0 = allow. Exit 2 = block, with stderr relayed back to the model.

payload=$(cat)

agent=$(printf '%s' "$payload" | jq -r '.agent_type // ""' 2>/dev/null)
[ "$agent" = "deliver-orchestrator" ] || exit 0

path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

case "$path" in
  */.claude/plans/*) exit 0 ;;
esac

echo "Blocked: deliver-orchestrator writes only .claude/plans/** (attempted: ${path:-<no path>}). Route this change through a Develop subagent (deliver step 03-develop.md) — applying a review finding by hand, however trivial, bypasses build and review." >&2
exit 2
