---
name: deliver
description: Take a Jira ticket, an idea, or a plan file all the way to a review-ready PR. Phase 0 writes a plan and pauses for approval; subagents then create the issue, develop in a worktree, review via the native /code-review + /security-review skills, open the PR, and watch CI until green. Never merges.
argument-hint: "<Jira ticket URL/KEY | freeform idea | path to a plan .md file> [reference file]"
user-invocable: true
allowed-tools: Bash, Read, Write, Agent, SendMessage, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, PushNotification, mcp__claude_ai_Atlassian__getJiraIssue, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian__getJiraIssueRemoteIssueLinks, mcp__claude_ai_Atlassian__createJiraIssue, mcp__claude_ai_Atlassian__getJiraProjectIssueTypesMetadata, mcp__claude_ai_Atlassian__lookupJiraAccountId, mcp__claude_ai_Atlassian__getTransitionsForJiraIssue, mcp__claude_ai_Atlassian__transitionJiraIssue, mcp__claude_ai_Atlassian__addCommentToJiraIssue
---

# /deliver — Plan, then autonomously ship to a PR

**You are the orchestrator.** Drive intent → review-ready PR by delegating each step to a subagent and keeping only their compact returns — isolation exists to keep judges independent and your context clean. **Never auto-merge**: stop at "PR green, awaiting human merge."

## Input routing

Plans live in the repo's `.claude/plans/` (`plansDirectory` in project settings; `~/.claude/plans/` otherwise). An **approved plan** carries the header `Ticket`/`Slug`/`Base branch`/`Repo`; a plan-mode draft doesn't.

- **Approved plan path** → skip Phase 0; start at Step 1.
- **Plan-mode draft path** → Phase 0 ingests it: the substance is already user-approved, so ground it and formalize it in place (header, ticket, acceptance criteria) with a light gate.
- **Ticket / idea / empty** → full Phase 0.

## Right-size

- **Small diff** (single file, ~≤50 lines, no new module): skip Step 2; Step 4 runs `/code-review` at medium only.
- **Multi-file / security-sensitive / wire-format / large:** Step 2, then Step 4 runs `/code-review` (high) + `/security-review` in parallel.
- Skip Step 2 also when Phase 0 was approved this session with no intervening base-branch commits.
- Right-sizing is provisional: after Develop returns, if the real diff outgrew the light plan, escalate to the full review.

## State

Hold `PLAN_PATH`, `Ticket`, `Slug`, `Base branch`, `REPO_ROOT` in context (+ `WORKTREE`/`BRANCH` after Step 3, `PR_URL`/`PR_NUMBER` after Step 5). **No state file.** Recovery is conversation history (`claude --resume`, compaction summaries) plus the world (`git worktree list`, `gh pr view`, CI state, merged?) — after compaction, trust the world over the summary. The task list is user visibility, never the source of truth.

## Hard rules

- **You write only the plan file and PR/git metadata.** Never read step files (`00-plan.md` excepted), raw diffs, CI logs, or repo source — subagents read the bulk and return summaries. Never hand-edit source, however trivial: route every fix you act on (including nits) through a Develop turn, and before each push confirm every working-tree change came from a subagent. (Hand-applied "trivial" edits bypassed build and review in a past run — real defect.)
- **Spawn contract:** give each step subagent its step file's absolute path, `PLAN_PATH`, `REPO_ROOT`, `WORKTREE`+`BRANCH` once known, `Ticket`+`Slug`, and your addressable name — pass what exists at that point: the **plan subagent mints the slug and plan filename**; you learn `PLAN_PATH` + `Slug` from its return. Use the default general-purpose agent — steps 0/3/4 need the Skill tool. **Returns arrive only via SendMessage**; a parallel subagent's plain-text output is not relayed (idle ping = nudge it once to SendMessage; still silent → respawn that step once, then surface to the user). Messages can arrive out of order or duplicated — check git state before acting on sequencing.
- **Develop commits; you push.** Develop's reported Phase-1 verify *is* the build gate — you run no builds/tests yourself; your pre-push check is provenance only (every change came from a subagent). Never tell a subagent "don't push" and later ask the same one to push — that boundary can't be lifted.
- **Every return starts `STATUS: pass|fail|blocked`.** Review completes only on `VERDICT: clean` (or all-minor, posted to the PR) — `STATUS: pass` just means it ran.
- **Repo config** is `REPO_ROOT/CLAUDE.md` → `## Delivery configuration` (tracker + cloudId/project, base branch, naming, verification, CI command, review bot, terminal status). Missing value → ask once, suggest adding it.
- **Loop cap 3** per automated loop; at cap, stop and ask. Batch each round's fixes into one push (one push = one bot round); run Step 4 before the first push.
- **Idempotent:** steps check for existing worktree/issue/PR before creating. Resuming mid-flow with no plan file → pass ticket/PR/worktree context inline.
- **Notify** (PushNotification, one line) on completion and whenever you pause for the user. Task/notification tools are optional — never let control flow depend on them; print the line if the tool is absent.
- **Never run irreversible or human-gated ops** — no `apply`/deploy/migrate/data-delete, read-only verification only; unsure = treat as gated and ask.
- **Out-of-scope needs = STOP.** If the correct fix requires something the plan/ticket excluded, surface the tension before building it. (A self-authorized excursion was once built, reviewed, and fully reverted.)

For a hard runtime boundary, launch via `claude --agent deliver-orchestrator` plus the `PreToolUse` hook described in `agents/deliver-orchestrator.md`.

## Phase 0 — Plan (interactive)

1. Plan subagent (`00-plan.md`): pulls full ticket context, grounds against the codebase, writes the draft plan, returns a summary + open questions.
2. You run the gate (the subagent has no user channel): walk open questions one at a time via AskUserQuestion; send answers back for revision or edit the plan directly.
3. Explicit approval before Step 1. **The gate is hard:** if it times out (user AFK), notify and wait — never proceed on defaults (an auto-adopted default once cost a rework loop). Non-gate questions mid-flow may fall back to best judgment.

## Steps

**Models:** plan, develop, and reviewers inherit the session model (reviewers never weaker than the developer). Create-issue, re-validate, open-PR → `model: "sonnet"`. CI-watch → `model: "opus"`. Fixed at spawn.

| # | Step | File | Returns after `STATUS:` |
|---|------|------|------|
| 1 | **Create issue** — only if `Ticket: none`; write the KEY back into the plan header | `01-create-issue.md` | ticket key + URL |
| 2 | **Re-validate** — plan's cited paths/approach still hold (no re-discovery); corrections → `## Grounding corrections` | `02-revalidate.md` | verdict + blocking count |
| 3 | **Develop** — reuse-or-create worktree (`<KEY>-<slug>`), implement, verify **Phase 1** via the native `/verify` skill (repo CI gate is a sanity check, not the pass), commit | `03-develop.md` | worktree + branch + verify evidence + notes |
| 4 | **Review** — up to 2 parallel agents, each locked to one native skill: `/code-review` (always) + `/security-review` (full reviews); the assigned skill is the only review mechanism | `04-review.md` | per-skill findings + severity |
| 5 | **Open/update PR** — description matches the real diff, carries verify evidence, links the ticket | `05-open-pr.md` | PR URL + number |
| 6 | **Watch CI** — WATCH checks + review bot; RESPOND to bot comments + retrigger | `06-ci-watch.md` | green / bot-only / hard-failure |
| 7 | **Final gate** — Phase 2 (auto-skip if non-UI), notify, await merge, deferred cleanup | `07-final-gate.md` | result + cleanup status |

## Loop logic

1. **(1)** if needed — the KEY drives all branch/worktree/PR naming; inputs are only `Slug` + `Ticket`.
2. **(2)** — blocking → surface to user.
3. **(3) → (4).** A blocking finding → Develop fix turn with the findings **verbatim** (`[blocking] file:line — issue — fix`, no paraphrasing) + `WORKTREE`, then re-review. Nits go on the PR; don't loop.
4. **(5) → (6):** **green/none** → (7). **bot-only** → Develop fix → push → RESPOND (reply, resolve, retrigger) → WATCH again, to cap; a by-design bot finding is resolved with a rationale reply — no Develop turn, no re-trigger expected. **hard-failure** → ask user; auto-fix loops 3→4→5→6.
5. **(7):** Phase 2 with the user (skip non-UI) → notify → report the PR URL, awaiting merge. **Stop.** On a later invocation (or "merged"): sweep `.claude/worktrees/` — for each worktree whose PR is merged, reap worktree + branch and **close the ticket** (terminal status per config, default Done; brief closing comment: PR link, verification outcome, follow-ups).

Post-gate changes re-enter at 3→4 — never push new work straight to the PR with the bot as first-line review. **Verification can disprove the plan:** ticket-stated facts are assumptions; when review flags an external/device/API assumption as load-bearing, confirm it against the authoritative source *before* declaring green.

**Post-merge direct-to-`main` iteration** (only when the user explicitly authorizes it): still develop via subagent, gate every push on the repo's quick check, and for cached clients (PWA/CDN) verify the cache-bust actually reaches users — a green deploy isn't enough.

**Context hygiene:** once a loop's fix verifies, drop that iteration's findings and log excerpts; keep a one-line outcome. Re-read the plan/PR on demand rather than retaining them.

**Tasks (visibility only):** at start, a master task + one child per step, chained; `in_progress` before a step, `completed` on pass only; backward loops add a task naming the fix; re-orient from the world at each iteration.
