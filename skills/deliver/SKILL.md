---
name: deliver
description: Use when the user wants to take a Jira ticket, an idea, or an existing spec file all the way to a review-ready PR (plan-and-ship), or to ship an already-approved spec. Phase 0 plans the work into a spec file and pauses for approval; then targeted subagents create the issue, develop in a worktree, run parallel multi-lens review, open/push the PR, and watch CI — looping on feedback until CI is green. Each step runs in its own subagent to protect the orchestrator's context and reduce bias.
argument-hint: "<Jira ticket URL/KEY | freeform idea | path to a spec .md file> [reference file]"
user-invocable: true
allowed-tools: Bash, Read, Write, Agent, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, PushNotification, mcp__claude_ai_Atlassian__getJiraIssue, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian__getJiraIssueRemoteIssueLinks, mcp__claude_ai_Atlassian__createJiraIssue, mcp__claude_ai_Atlassian__getJiraProjectIssueTypesMetadata, mcp__claude_ai_Atlassian__lookupJiraAccountId
---

# /deliver — Plan, then autonomously ship to a PR

**You are the orchestrator.** Your job is to drive the work from intent → review-ready PR, running each unit as a **subagent** so detail stays **isolated** in that subagent and you accumulate only compact structured results. Subagent isolation costs tokens (cold re-reads, ~several× a single agent) — you spend that deliberately, to keep judges independent and your own context uncluttered, **not** because it is cheaper. Apply it where it earns its keep (see "Right-size the work"). **Never auto-merge** — you stop at "PR green, awaiting human merge."

## Input routing (do this first)

- **Arg is a path to an existing `.md` spec file** → skip Phase 0; start at Step 1 (the spec is already approved).
- **Arg is a Jira ticket (URL/KEY), a freeform idea, or empty** → run **Phase 0** to produce and get approval on a spec file, then continue to Step 1.

## Right-size the work (do not pay multi-agent cost you don't need)

Multi-agent fan-out is for diffs that are large, security-sensitive, or touch wire formats — there the isolation and independent judgment demonstrably improve the outcome. Scale the machinery to the change:

- **Small diff** (single file / ~≤50 lines / no new module, per the spec's "Files to touch"): **skip Step 2**, and in Step 4 run **one correctness reviewer**, not three. The develop subagent's self-review is enough for the other lenses at this size.
- **Multi-file / security-sensitive / wire-format / large diff:** run the full Step 2 + 3-lens parallel review.

When unsure, ask the user once (AskUserQuestion: light vs full review). Default light for obvious small changes.

## Orchestrator state (held in context AND persisted to a state file)

Read the spec header **once** and keep: `SPEC_PATH`, `Ticket`, `Slug`, `Base branch`, `REPO_ROOT` (the spec's `Repo` — where CLAUDE.md lives). After Step 3 returns, also keep `WORKTREE` and `BRANCH`; after Step 5, `PR_URL` + `PR_NUMBER`. From CLAUDE.md keep `REVIEW_BOT` + its retrigger command.

**The durable store is a state file, not context or task metadata.** Compaction and crashes wipe working context. Write run state to a sidecar file next to the spec — `<SPEC_PATH without .md>.state.md` (in `REPO_ROOT/.claude/specs/`, already gitignored — but when you're operating inside a worktree, or the repo's CLAUDE.md forbids writing to the main checkout from a worktree, put it in the **worktree's** `.claude/specs/` instead) — as plain `- **Key:** value` lines (`Ticket, Slug, BaseBranch, RepoRoot, Worktree, Branch, PrUrl, PrNumber, ReviewBot, Step`). Update it the moment you learn a value (esp. `Worktree` after Step 3, `PrUrl` after Step 5). **Re-read it after any compaction or on re-invocation** to restore state. This follows Anthropic's long-running-agent guidance (persist recovery state in file artifacts + git, not ephemeral context). Everything else lives in the spec file (re-read on demand). The task list (below) mirrors progress for visibility but is **not** the source of truth.

## Operating rules

- **Never read the `NN-*.md` step files yourself** (Phase 0 / `00-spec.md` is the one exception — see below). For each step, launch a subagent and pass in the prompt: (1) `SPEC_PATH`, (2) the **absolute path to that step's file** (resolve from this skill's directory), (3) `REPO_ROOT`, (4) `WORKTREE`+`BRANCH` once known, (5) `Ticket`+`Slug`. The subagent reads its own step file. You only receive its compact return.
- **Subagents must deliver their return via SendMessage, not stdout.** A background / parallel subagent's plain-text output is **not** relayed to you — you'll get only idle pings and the run stalls. Instruct every step subagent (especially the three parallel reviewers) to send its `STATUS:`-prefixed return by calling SendMessage to you (the orchestrator / `team-lead` / `main`). If one goes idle without sending, nudge it once to SendMessage rather than waiting.
- **Never read raw diffs, CI logs, or large files yourself.** That is what the subagents are for — they read the bulk and hand you a short summary. Pulling a full diff or CI log into your own context defeats the isolation and rots it. If you need a fact from one, ask the relevant subagent for it.
- **REPO_ROOT vs WORKTREE.** `REPO_ROOT` is the main checkout (read CLAUDE.md, derive config; any sibling repos/dependencies declared in CLAUDE.md are relative to it). `WORKTREE` is created by Step 3 and is where all git/build/edits happen for steps 3–6. Tell every step which to use. **All file writes for the feature stay inside `WORKTREE`; the spec file (in REPO_ROOT) is written only in Phase 0 / Step 1.**
- **Pushing is the orchestrator's / Step 5's job, not the develop subagent's.** Tell Develop to **commit only**. Never instruct a subagent "do not push" and then later ask the *same* subagent to push — a step-level "do not push" boundary can't be lifted by a follow-up message (the permission layer treats it as fixed). The orchestrator pushes instead, after a quick syntax/build check.
- **Uniform status.** Every step's return starts with `STATUS: pass | fail | blocked`. Mark its task `completed` only on `pass`.
- **Repo config lives in `REPO_ROOT/CLAUDE.md`** under `## Delivery configuration` (issue tracker + cloudId/project, base branch, branch/worktree naming, verification method, CI status command, review bot + retrigger). If a required value is missing, the step asks the user via AskUserQuestion, then proceeds — and suggests adding it to CLAUDE.md.
- **Loop cap + batch.** Cap each automated loop (review→develop, CI→develop, bot-review) at **3 iterations**. On the 3rd failure, stop and surface to the user via AskUserQuestion instead of looping again. **Batch all fixes for one round into a single push before retriggering the bot** — one push = one bot round; pushing per-fix multiplies the rounds. Run the internal 3-lens review *before* the first push so findings are caught before the bot, not after.
- **Idempotent / resumable.** Re-invoking `/deliver` on the same spec must not double-create. Steps check first: existing worktree (`git worktree list`), existing issue (`Ticket:` in spec), existing PR (`gh pr view`). On re-invocation, **read the state file** (`<spec>.state.md`) to restore `Worktree`/`Branch`/`PrUrl`/`Step`, then resume from the first incomplete step. When asked to **resume mid-flow with no Phase-0 spec** (e.g. "start at the review step" on an existing PR), there is no `SPEC_PATH` — pass the ticket / PR + branch / worktree context **inline** to step subagents in place of the spec, and still write a minimal state file so the run stays resumable.
- **Degrade gracefully on optional tools.** The Task tools (`TaskCreate/Update/List/Get`) and `PushNotification` are *conditionally* available — they may be absent in some harnesses. Never make control flow *depend* on them: the **state file** is the resume mechanism (tasks are visibility-only), and if `PushNotification` is unavailable, fall back to printing the one-line status to the user.
- **Notify when you finish or need the user.** This runs autonomously for many minutes; the user will step away. Send a **PushNotification** (a) on completion (final gate done), and (b) whenever you pause for the user — an AskUserQuestion blocking decision, a hard failure, or a loop hitting its cap. Keep it one line ("<KEY>: PR green, awaiting your merge" / "<KEY>: CI failed 3× — needs you"). If the repo or user defines a notify hook, the harness fires it; don't hardcode a script path. If the tool isn't available, just print the line.
- **Never run irreversible or human-gated operations autonomously.** Some repos' verification/deploy is destructive — `terraform apply`, infra deploys, DB migrations, data deletes. For verification run only the **read-only** checks the repo declares (build, lint, `validate`, `plan`, tests); **never `apply`/deploy/migrate.** If a repo marks such steps human-gated, stop and hand them to the user at the final gate. When unsure whether an action is reversible, treat it as gated and ask.
- **Surface decisions, don't bury them.** On a blocking gap or hard failure, bring it to the user with AskUserQuestion before burning another develop loop — unless the fix is unambiguous. **When the correct fix needs a capability the spec/ticket explicitly *excluded*** (a new wire format/opcode, an out-of-scope path), STOP and surface it as a spec-tension ("expand scope, or ship the spec + file a follow-up?") **before building it** — never expand protocol/wire-format scope autonomously. (A self-authorized out-of-scope excursion was the single biggest cost sink in a past run — built, reviewed, then fully reverted.)
- **Bright line — the orchestrator writes only the state file, the spec file, and PR/git metadata** (`gh`, push, branch/worktree ops via `Bash`). Every read, edit, build, or test of repo *source* is subagent work — **no size exception.** "This fix is one line, too trivial to spin up a subagent" is the exact rationalization that leaks step-work in; triviality is never a reason to do it yourself. **Applying a review finding is subagent work too** — never hand-edit source to clear a nit; route every finding you act on (blocking or minor) through a Develop fix turn, batched one turn per round. **Reading a source file to place an edit is the tripwire:** if you're doing it, stop and write a fix instruction to a subagent instead; if you only need a fact from a file, ask the subagent for it. **Before every push, self-check** that every working-tree change this round came from a subagent — a hand-made change means you defected: revert it and delegate. (Hand-applied "trivial" orchestrator edits bypass the build *and* the reviewer — a real defect in a past run.)

## Runtime enforcement (optional): constrained-orchestrator launch

The bright line above is instruction-level. For a hard runtime stop, launch the orchestrator as a named agent — `claude --agent deliver-orchestrator` (see `agents/deliver-orchestrator.md`) — instead of as a main-session skill. Two facts (confirmed against the harness docs) shape what this can and can't guarantee:

- **Per-agent tool grants are not path-scoped, and the orchestrator legitimately needs `Write` (state/spec file) and `Bash` (git/`gh`).** A toolset alone therefore cannot express "write state, never source" — omitting `Edit` narrows the easy path, but `Write`/`Bash` remain escape hatches.
- **Airtight enforcement needs a companion `PreToolUse` hook.** Subagent tool calls carry an `agent_type` in the hook payload. A hook on `Edit|Write` that blocks paths outside `.claude/specs/**` **only when the caller is the orchestrator agent** constrains it while leaving develop subagents and ordinary sessions untouched. **Before relying on this, verify on your harness version that a `--agent`-launched main thread actually reports its `agent_type` to hooks** — if it presents as an unlabelled main session, the hook cannot tell it from normal coding and must instead be gated on a run marker the skill writes at start and clears at the final gate. Until that is verified, the instruction bright line is the primary control.

## Phase 0 — Spec (interactive; produces the approved spec file)

Skip entirely if the input was already a spec file.

1. Launch a **spec subagent** with `00-spec.md`, the raw input (ticket/idea + any reference file), and `REPO_ROOT`. It pulls ticket context (all comments + linked tickets), grounds against the codebase via Explore, **writes a draft spec file**, and returns a compact summary + an **open-questions** list.
2. **Run the approval gate yourself** (you have the user channel; the subagent doesn't): walk the open questions with AskUserQuestion, one decision at a time. Send answers back to the spec subagent (SendMessage) for revision, or apply small edits to the spec file directly.
3. When no open decisions remain, present the final spec for **explicit approval** (AskUserQuestion: approve / revise). Do not proceed to Step 1 until approved. The approved spec's `SPEC_PATH` + header become your state.

## Steps (autonomous; each a subagent)

| # | Step | File | Returns (after `STATUS:`) |
|---|------|------|------|
| 1 | **Create issue** — only if `Ticket: none`. Create the tracking issue from the spec; write the KEY back into the spec header. If the spec has a ticket, skip and reuse it. | `01-create-issue.md` | ticket key + URL |
| 2 | **Re-validate** — cheaply re-check the spec's cited paths still exist and the approach still holds (do NOT re-discover). Write any corrections into the spec under `## Grounding corrections`. | `02-revalidate.md` | verdict + blocking count |
| 3 | **Develop** — reuse-or-create the worktree (`<KEY>-<slug>`), implement, run **verify Phase 1 only** (build/deploy/logs/tests — headless), commit. | `03-develop.md` | `WORKTREE` + `BRANCH` + verify evidence + impl notes |
| 4 | **Review** — **3 parallel** reviewers on the diff, one lens each: **security**, **simplification**, **correctness**. Give the **correctness** reviewer the develop step's `VERIFY:` evidence line (so it independently checks the author's self-verification); give security/simplification the diff only, no spec narrative. | `04-review.md` | per-lens findings + severity |
| 5 | **Open / update PR** — open the PR (or push if it exists); description matches the real diff, carries the Phase-1 verify evidence, links the ticket. | `05-open-pr.md` | PR URL + number |
| 6 | **Watch CI** — WATCH until checks + review bot settle; RESPOND to bot comments + retrigger. | `06-ci-watch.md` | green / bot-only / hard-failure |
| 7 | **Final gate** — verify **Phase 2** (user UI confirmation, auto-skip if spec touches no UI), notify completion, report "PR green, awaiting your merge", and reap the worktree once the PR is merged. | `07-final-gate.md` | confirmation result + cleanup status |

## Loop logic

1. **Create issue (1)** if needed — its KEY drives all branch/worktree/PR naming. Naming inputs are **only** `Slug` + `Ticket`; no step invents its own slug.
2. **Re-validate (2).** If blocking, surface to user (revise spec / proceed with notes).
3. **Develop (3) → Review (4).** Capture `WORKTREE`+`BRANCH` from (3) and thread them everywhere after. If any reviewer returns a **blocking** finding, send a fix back to Develop (3) — passing the blocking findings **verbatim** (`[blocking] file:line — issue — fix`), do not paraphrase or filter them — plus the existing `WORKTREE`. Then re-review (4). Repeat until clean or the loop cap; non-blocking nits go on the PR, don't loop.
4. **PR (5).**
5. **CI (6):**
   - **green** / **none** (repo has no CI checks) → go to Final gate (7).
   - **bot-only** (only the review bot blocks; all automated checks pass) → dispatch a Develop fix turn (3) with the bot comments + `WORKTREE` → push (5) → run (6) in **RESPOND** mode (reply, resolve, retrigger) → run (6) in **WATCH** mode again (waiting for a review newer than the retrigger). Loop to cap. **A bot finding that is intended / by-design needs no Develop turn** — reply on its thread with the rationale and resolve it (RESPOND-only); that's a valid terminal resolution, so don't loop or expect a re-trigger to clear it.
   - **hard-failure** (a test/lint/build check failed) → surface to user (auto-fix via Develop / stop). If auto-fixing, loop 3→4→5→6.
6. **Final gate (7):** run verify Phase 2 with the user (skip if non-UI), then notify + report the green PR URL and that it awaits their merge. **Stop — do not merge.** Worktree cleanup is deferred until the PR is merged: leave the run open (`Step: awaiting-merge`), and **on a later `/deliver` invocation (or when the user says it's merged) first check the state file's `PrNumber` — if `gh pr view` shows merged, reap the worktree + branch and mark the run complete** before doing anything else.

**The final gate is terminal for the flow, not for quality.** Don't declare "awaiting merge" while fix work is still in flight. Any new or user-requested change after the final gate **re-enters at Step 3→4** (develop → review) — never push new work straight to the PR using the review bot as first-line review.

**Verification can disprove the spec.** Phase 2 (real-device / manual) — and user testing after merge — can reveal that a ticket-stated fact (a data format, a field, device behaviour) doesn't match reality. Treat ticket constraints as **assumptions to verify**, not ground truth; when one is wrong, loop back with a fix (a develop turn / follow-up) rather than forcing the spec. For physical/hardware/3rd-party-integration features, ground the assumption against real data before relying on it. **When a correctness reviewer flags an external/device/API assumption as "load-bearing," treat it as a verification gate, not a shippable comment** — confirm it against the authoritative source (firmware/docs/real data) *before* declaring the PR green, not after. An identity/dedup/format key resting on an unverified external field is the classic trap; ground it first.

## Post-merge iteration on a live app (only when the user explicitly authorizes direct-to-`main`)

The default is always PR-based. But after the PR merges and the app is deployed, the user often wants fast follow-up fixes — and may explicitly authorize committing straight to `main` (typical for a small internal tool). Only then:

- Still make changes via a develop subagent (or precise edits), but **gate every push behind the repo's Phase-1 check** (syntax/build/lint) yourself so a broken commit can't hit the live site. Skip the formal PR/review cycle per the user's call; keep security-relevant changes reviewed when feasible.
- **Confirm the change actually reaches users.** A green deploy is not enough for cached clients: for PWAs / static deploys, changing a precached asset does nothing until you **bump the cache / service-worker version** (or invalidate the CDN). Verify both the deploy *and* the cache bust.
- Before starting new direct-to-`main` work, reap any worktree/branch from the now-merged PR and re-read the state file.

**Compaction (context hygiene across loops).** Context is a finite resource — stale detail degrades recall. After a backward loop's fix is verified, **drop that iteration's reviewer findings and CI log excerpts** from your working notes; keep only a one-line outcome (e.g. `loop 2: fixed <file>:<line>, re-review clean`). Never carry a prior iteration's full findings into the next. The spec file and PR are the durable record — re-read them on demand rather than retaining their content.

## Progress tracking (the state file is truth; tasks are visibility)

The **state file** (`<spec>.state.md`, see Orchestrator state) is how you know "where am I" across loops, compaction, and re-invocation — update its `Step` field as you advance and never infer position from memory. The task list mirrors this for the user's benefit and degrades gracefully if Task tools are absent.

1. **At start**, write the state file, then (if Task tools exist) TaskCreate a **master task** `"Deliver: <spec title>"` (`in_progress`) plus one child task per step (Spec if Phase 0 runs, Create issue, Re-validate, Develop, Review, Open PR, Watch CI, Final gate), chained with `addBlockedBy`. Immediately complete/skip Create-issue if the spec already has a ticket.
2. **Write new state to the file as you learn it** (`Worktree` after Step 3, `PrUrl` after Step 5, `Step` after each). This is the durable record that survives compaction/crash.
3. **Before a step's subagent**, set its task `in_progress`; **after a `pass` return**, set it `completed` and update the state file. Never complete a task on `fail`/`blocked` (e.g. Develop on `VERIFY: fail`, Review with unresolved blocking findings).
4. **On a backward loop**, set Develop/Review/Open-PR back to `pending`/`in_progress` and TaskCreate a new task naming the specific fix (e.g. "Fix: review-bot comment <file>:<line>") so the list records *why* it's repeating. Respect the 3-iteration cap.
5. **Re-orient from the state file** (`Step`) and TaskList at the top of each loop iteration; act on the first unblocked incomplete step. **On re-invocation**, restore from the state file before resuming.
6. **All steps complete** (CI green + final gate done) before telling the user it's ready to merge. Keep the run open (master task `in_progress`, state file `Step: awaiting-merge`) until the worktree is cleaned up after merge (see Step 7); only then mark complete.
