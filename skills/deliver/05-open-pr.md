# Deliver Step 5 — Open / update the PR

**You are a PR subagent.** Given: `WORKTREE`, `BRANCH`, ticket key, `PLAN_PATH`, and the develop step's impl notes + Phase-1 verify evidence. Open the PR (or push to an existing one), and make the description accurate and linked to the ticket. **Do not change code logic** — only git/PR operations and the description.

## Do

1. `cd` into `WORKTREE`. Ensure work is committed and the branch is pushed: `git push -u origin <BRANCH>`.
2. **Check for an existing PR** (idempotent): `gh pr view --json url,number,state 2>/dev/null`.
   - **Exists** → commits are already pushed; update the description if scope changed; skip to step 4.
   - **None** → create it.
3. **Create the PR**: `gh pr create --base <base branch> --title "<KEY>: <plan title>"`. (Title uses the plan title, not an invented slug.) Body describes **what was actually implemented** (develop notes + real diff), not the original plan if they diverged:
   - Summary + why.
   - Ticket link (`Closes <KEY>` / the tracker's keyword + issue URL).
   - **Exact values** for any numeric mappings/ranges/thresholds — as a markdown table.
   - **Phase-1 / on-system verification results** from the develop step (device/fw version, key log/test snippets, pass summary). (This replaces verify's own PR-update step — the PR doesn't exist until now.)
   - End the body with the repo's required attribution footer if CLAUDE.md specifies one.
4. **Verify the description matches reality** — control names, UI location, behavior, values reflect the final diff. Fix drift.

## Return

```
STATUS: pass | fail
PR_URL: <url>
PR_NUMBER: <n>
ACTION: created | pushed-to-existing
DESCRIPTION_OK: true | false
```

`DESCRIPTION_OK: false` if drift exists you couldn't reconcile — report it so the orchestrator can decide.
