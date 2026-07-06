# Deliver Step 7 — Final gate (Phase 2 verify + notify + await merge + cleanup)

This step runs **at the orchestrator level, not in a headless subagent** — it needs the user channel. (It's described here so the orchestrator follows it consistently.)

CI is green. Close the verification loop, hand off to the human, and reap the worktree once merged. **Never auto-merge.**

## Do

1. **Decide if Phase 2 is needed.** Read the spec's `## Files to touch` / `TOUCHES_UI` flag.
   - **No UI touched** (pure data/protocol/logic) → Phase-1 evidence is sufficient; **auto-skip** Phase 2. Say so.
   - **UI touched** → run **verify Phase 2**: ask the user to confirm the UI renders and behaves as expected, summarizing the Phase-1 findings and what to look at. Offer clear options (works / has an issue / skip — logs sufficient). Use the Phase-2 wording from the repo's verify recipe (its `verifier-*` skill under `.claude/skills/`) if it has one.
2. **If the user reports a UI issue** → dispatch a Develop fix turn (Step 3) with the specifics + existing `WORKTREE`, then re-run Review (4) → push (5) → CI (6) → back here. Respect the loop cap.
3. **When confirmed (or skipped)** → **PushNotification** the user (one line, e.g. `<KEY>: PR green, awaiting your merge`) and report:
   - The **PR URL**, what passed (checks + review bot, or "no CI on this repo"), and the verification summary.
   - That it is **awaiting their merge** — `/deliver` does not merge. Per repo policy, merging is the human's call.
   - **Any human-gated steps the repo declares** (e.g. run `terraform plan` and check the destroy count, then `apply`; trigger a deploy; run a migration). Spell out exactly what to run and check before they merge/apply — `/deliver` never ran these.
4. **Defer cleanup; keep the run open.** Set the state file's `Step: awaiting-merge` (and leave the master task `in_progress` if Task tools exist). The worktree must survive until the PR merges.

## Deferred cleanup (runs on a later invocation, or when the user says "merged")

Before starting any new work, the orchestrator reads the state file and checks the PR:
- `gh pr view <PrNumber> --json state,mergedAt` — if **merged**:
  1. `git worktree remove <Worktree>` (add `--force` only if it refuses due to untracked build artifacts) and `git branch -D <Branch>`. **But if this session is itself running inside `<Worktree>`, do NOT remove it** — you'd be deleting your own checkout (and the remove fails). Mark the state complete, report that cleanup is deferred, and reap it from a session started in `REPO_ROOT` (or another worktree).
  2. **Close the ticket.** `getTransitionsForJiraIssue` → `transitionJiraIssue` to the repo's terminal status (from `## Delivery configuration`; default **Done**), then `addCommentToJiraIssue` with a brief closing comment: what shipped (PR link), verification outcome, follow-ups. If the transition tools are unavailable, tell the user the ticket still needs closing.
  3. Mark the run complete (state file `Step: done`; master task `completed` if present).
  4. Tell the user the worktree/branch were reaped and the ticket closed.
- If **not merged**, leave everything as-is.

This keeps `.claude/worktrees/` from accumulating stale trees across many shipped features. Never reap a worktree whose PR isn't merged.

## Return (orchestrator's own summary to the user)
```
STATUS: pass
PR: <url>
VERIFIED: phase1 + phase2 | phase1 (UI confirmed) | phase1 (non-UI, phase2 skipped)
NEXT: awaiting human merge
CLEANUP: deferred | done (worktree + branch reaped)
```
