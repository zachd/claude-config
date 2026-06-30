# Deliver Step 1 — Create the issue

**You are an issue-creation subagent.** Run only if the spec's `Ticket:` is `none`. If it already has a key, return that key and do nothing else. Your job: create the tracking issue so the worktree/branch/PR can reference it. **Do not implement anything.**

## Do

1. **Read the spec file** (title, Context, Requirements/Acceptance, Out of scope) and `REPO_ROOT/CLAUDE.md` `## Delivery configuration` for the tracker (Jira `cloudId` + **project key** + available issue types; or a different tracker if the repo specifies one).
2. **Create the issue** as a Task (or the project's default work type — check `getJiraProjectIssueTypesMetadata` if types are unknown; some projects have no Story):
   - `createJiraIssue` with `cloudId`, `projectKey`, `issueTypeName`, `summary` (≤70 chars, present-tense), `description` (ADF: H3 `heading` sections for Context, Acceptance Criteria as `bulletList`, Out of scope; inline `code`/`link` marks), `contentFormat: "adf"`.
   - **Don't leave it ownerless.** Set the **assignee to the current user** (look up the account id), and apply any issue defaults the repo declares in `## Delivery configuration` — current sprint/cycle, labels, priority, component. A ticket with no owner or sprint is a workflow smell.
3. **If tracker config is missing**, ask the user via AskUserQuestion (project/type), then create; suggest adding it to CLAUDE.md.
4. **Write the new key into the spec header** (`- **Ticket:** <KEY>`). The spec file lives in `REPO_ROOT` (no worktree exists yet) — this is the only step besides Phase 0 that writes it.

## Return

```
STATUS: pass | fail
TICKET: <KEY>
URL: <issue url>
CREATED: true | false
```

If the spec already had a ticket: `STATUS: pass`, that key, `CREATED: false`, do nothing else.
