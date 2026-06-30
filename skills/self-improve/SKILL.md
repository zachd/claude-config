---
name: self-improve
description: Use at the end of a session, or when the user says "self-improve" / "learn from this" / "what would you fix", to mine the conversation for recurring corrections and avoidable mistakes and propose targeted updates to the repo's agent instructions (CLAUDE.md / AGENTS.md) or its skills so future sessions start smarter. Also triggered implicitly when the user says "always" in a correction.
argument-hint: "[optional: focus area]"
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Edit, Write, AskUserQuestion
---

# /self-improve

**Goal:** Mine the current conversation for recurring corrections and avoidable mistakes, then update the project's persistent agent memory (its `CLAUDE.md`/`AGENTS.md`, or a relevant skill/command file) so the next session starts smarter.

This skill is repo-agnostic. Find the repo's instruction file (`CLAUDE.md`, else `AGENTS.md`, else the closest equivalent) and its skills/commands directory before proposing edits.

## When to run

- User invokes `/self-improve` or asks "what would you change for next time".
- User says **"always"** in a correction — treat it as an implicit trigger; capture the instruction immediately.
- End of a long session with many back-and-forth corrections.
- After a review surfaced patterns worth capturing.

## Process

### 1. Gather evidence
Scan the conversation (and transcript if available) for these signals — each is a potential learning:

| Signal | What to look for |
|--------|-----------------|
| **User correction** | "no", "don't", "actually", "stop"; user reverses an agent action |
| **Repeated ask** | User requests the same thing twice (agent missed it or did it wrong) |
| **Build/lint/test error from agent code** | Agent introduced an error the user had to report |
| **API/tooling misuse** | Wrong API, wrong dependency syntax, wrong framework/library pattern for this stack |
| **Over-eagerness** | Agent removed/changed something it wasn't asked to (e.g. deleting shared/generated code) |
| **Preference** | User corrected a stylistic/UX/structural choice |
| **Workflow friction** | Agent asked something it could have answered from existing context |

For each: **what happened** (1 line), **what should have happened** (1 line), **where to capture it** (the instruction file, a specific skill/command, or a new rule).

### 2. Classify and deduplicate
Group findings (code conventions → instruction file; architecture → instruction file or the relevant skill; workflow/process → the skill's own file or a process section). **Drop anything already captured. Drop anything too narrow to recur.**

### 3. Apply changes
Split into two buckets:
- **Certain** — clear, recurring corrections (e.g. "always build after tasks", "never edit X"). Apply directly without asking.
- **Uncertain** — ambiguous or one-off; confirm via **AskUserQuestion** before applying.

**Rules for good entries:**
- Imperative voice ("Check X before Y", not "We learned that X").
- General principles over narrow wording — avoid exact error strings or one-off paths unless the mistake only recurs in that exact form.
- Concrete and actionable; no narrative. Keep to 1–2 lines.
- Place near related bullets so the agent sees it in context. Keep the instruction file tight.

Apply certain changes immediately, then present uncertain ones via **AskUserQuestion**. After all edits, read back the modified files to confirm, and offer to commit with a message like `chore: self-improve — update agent instructions from session learnings`.

## Quality bar
Every addition must pass all three — if it fails any, drop it:
1. **Crucial** — would the agent repeat this mistake without the reminder?
2. **Concise** — one line, imperative, no narrative.
3. **General** — likely to recur across sessions, not a one-off. Prefer a principle over a recipe.

After edits, re-read the full instruction file. If it's growing bloated, consolidate or remove entries that are now obvious or redundant.
