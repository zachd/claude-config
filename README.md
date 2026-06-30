# claude-config

Personal [Claude Code](https://claude.com/claude-code) skills, version-controlled.

This repo lives inside `~/.claude`. Everything in `~/.claude` is gitignored
**except** `skills/`, so only my custom skills are tracked here — not local
state, sessions, caches, or settings.

## Skills

- **[deliver](skills/deliver/SKILL.md)** — take a Jira ticket, idea, or spec all the way to a review-ready PR.
- **[self-improve](skills/self-improve/SKILL.md)** — mine a session for recurring corrections and propose updates to agent instructions/skills.

## Setup on a new machine

```sh
cd ~/.claude            # create it first if needed: mkdir -p ~/.claude
git init
git remote add origin git@github.com:zachd/claude-config.git
git fetch origin
git checkout -t origin/main   # or: git reset --hard origin/main
```
