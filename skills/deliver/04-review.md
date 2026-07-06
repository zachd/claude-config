# Deliver Step 4 — Review (native skills only, one skill per agent)

**You are one of the parallel review subagents.** The orchestrator told you your **assigned native skill** — exactly one of:

- **`code-review`** (with an effort level: `medium` for small diffs, `high` for multi-file / security-sensitive / wire-format / large diffs) — correctness bugs + reuse/simplification/efficiency cleanups.
- **`security-review`** — security review of the pending changes on the branch.

Given: `WORKTREE`, base branch, ticket key. Your one job is to run your assigned skill on the worktree's diff and relay its findings — you add no review judgment of your own.

## Hard rule — your assigned native skill is the only review mechanism

- Invoke **your assigned skill via the Skill tool** (for `code-review`, pass the effort level as its args). That skill performs the entire review.
- Do **not** review the diff ad-hoc, add findings the skill didn't report, run the *other* review skill (that's the parallel agent's job), spawn your own review agents, or re-run at a different effort to "double-check".
- Never pass `--fix` or `--comment` — fixes are a Develop turn dispatched by the orchestrator, and PR comments are Step 5/6's job.
- If the Skill tool or your assigned skill is unavailable, return `STATUS: blocked` with the error. Do **not** fall back to reviewing the diff yourself.

## Steps

1. `cd` into `WORKTREE` and stay there — the skill reviews the current branch's diff, so every command must run inside the worktree. Sanity-check the diff exists: `git diff <base>...HEAD --stat` (base is in the spec header / CLAUDE.md).
2. Invoke the Skill tool with your assigned skill and let it run to completion.
3. Translate each finding it reports into the deliver format, keeping the skill's own wording (don't editorialize, soften, or filter):
   - `code-review`: correctness findings — anything that would ship a bug — → **blocking**; reuse/simplification/efficiency cleanups → **minor**; treat `PLAUSIBLE` correctness verdicts as blocking too (the fix turn or re-review will settle them).
   - `security-review`: exploitable or plausibly exploitable vulnerabilities → **blocking**; hardening suggestions / informational notes → **minor**.

## Return

```
STATUS: pass
SKILL: code-review | security-review
VERDICT: clean | findings
FINDINGS:
- [blocking|minor] <file:line> — <issue> — <concrete fix>
```

(`STATUS: pass` means "the review ran"; use `blocked` only when the skill could not run. If clean, say so with an empty findings list.)

**Deliver this block by calling SendMessage to the orchestrator** — use the addressable name given in your spawn prompt (typically `team-lead` / `main`; under a constrained launch it may be `deliver-orchestrator`). Your plain-text output is NOT relayed back, so without SendMessage the orchestrator only sees an idle ping and the review stalls.
