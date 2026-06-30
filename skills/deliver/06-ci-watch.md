# Deliver Step 6 — Watch CI and handle the review bot

**You are a CI-watch subagent.** Given: `WORKTREE`, PR number/URL, ticket key. The orchestrator runs you in one **mode**:

- **WATCH** — poll the PR's checks until they settle, then classify.
- **RESPOND** — after a fix was pushed, reply to the review bot's comments, resolve them, retrigger.

Read `REPO_ROOT/CLAUDE.md` `## Delivery configuration` for the **CI status command**, the **required checks**, and the **review bot name + retrigger command**. Default to GitHub + `gh`. **If no review bot is configured, there is no `bot-only` branch** — outcomes are only `green` or `hard-failure`. **If the repo declares no CI / no automated PR checks at all** (e.g. infra repos with CLI-driven remote runs), there is nothing to watch — return `STATUS: pass`, `CI: none`, and let the final gate hand off to the human (don't poll for checks that will never appear).

---

## WATCH mode

You may be told this is a **post-retrigger watch** and given a **retrigger timestamp**.

1. `cd` into `WORKTREE`. Poll, e.g. `gh pr checks <n> --watch` or loop `gh pr checks <n> --json name,state,conclusion` with a short sleep. Fetch the configured bot's review: `gh pr view <n> --json reviews,statusCheckRollup` and inline comments via `gh api repos/{owner}/{repo}/pulls/{n}/comments`. The bot's **summary review** (and its `submitted_at` / `commit_id`, needed for the post-retrigger "newer than" check) is most reliably read via `gh api repos/{owner}/{repo}/pulls/{n}/reviews` — `gh pr view --json reviews` can miss it.
2. **Settle condition:** no pending/in-progress checks **and** the review bot has posted. **If this is a post-retrigger watch, only settle once a bot review *newer than the retrigger timestamp* exists** — do not classify against the stale prior review (avoids a false `green`).
3. **Classify:**
   - **green** — all required checks pass and the bot review has no unresolved **blocking** comments. (Nit-level bot comments don't block.)
   - **bot-only** — the only blockers are the bot's blocking comments; every automated check (tests/lint/build) passes. Collect those comments.
   - **hard-failure** — a test/lint/build check failed.

### WATCH return
```
STATUS: pass
CI: green | bot-only | hard-failure
CHECKS: <name: conclusion, …>
BOT_COMMENTS:            # bot-only only
- id: <id> | thread: <node id> | file:line | <text> | <planned fix>
FAILURE_DETAIL:          # hard-failure only
- <check> — <log excerpt>
```

---

## RESPOND mode

Given the bot comments that were addressed (fix already pushed). For **each**:
1. **Reply** on the thread stating what changed + the commit/file (`gh api repos/{owner}/{repo}/pulls/{n}/comments/{id}/replies -f body=...` or the equivalent review-comment reply). If the orchestrator **declined** a finding as intended/by-design (no code change), reply with that rationale instead of a fix reference — a valid resolution that ends the thread.
2. **Resolve** the thread (GitHub: `gh api graphql` `resolveReviewThread` mutation with the thread node id).
3. After all replies/resolves, post **one top-level** retrigger comment using the command from CLAUDE.md (default `gh pr comment <n> --body "@cursor review"`). **Record the timestamp of this comment** and return it — the next WATCH uses it as the retrigger timestamp.

### RESPOND return
```
STATUS: pass
REPLIED: <count>
RESOLVED: <count>
RETRIGGERED: true
RETRIGGER_TS: <iso timestamp of the retrigger comment>
```

---

## Rules
- Don't busy-poll forever — if checks hang well past normal runtime, return `hard-failure` with that detail so the user can decide.
- `bot-only` only when **every** non-bot check is genuinely green. A real test failure is always `hard-failure`.
- Never resolve a bot comment you didn't actually address — either by a pushed fix or an explicit, stated by-design rationale.
