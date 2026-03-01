---
name: multirepo-space
description: |
  Scaffold and manage multi-repo workspaces for AI coding agents.
  Orchestrates workspace-setup.sh (infrastructure) and agent-factory CLI (agents).
  Use when user says "create workspace", "setup multirepo", "multi-repo workspace",
  "add repo to workspace", "remove repo from workspace",
  "workspace status", "check workspace health", "init multi-repo",
  "orchestrate repos", "link repositories".
  Also use when user has multiple repos and needs a central
  coordination point for AI agents (Claude Code, Codex, Gemini CLI).
---

# multirepo-space

## Tools

This SKILL orchestrates two tools:
- `workspace-setup.sh` — bundled script for workspace infrastructure (dirs, symlinks, settings.json, AGENTS.md/CLAUDE.md)
- `agent-factory` — npm CLI for creating AI agents (`npx @tacuchi/agent-factory`)

## Quick routing

User intent → Action:
- "Create/scaffold workspace" → **Full setup flow**
- "Add a repo" → **Add flow**
- "Remove/detach repo" → **Remove flow**
- "Check/verify/health" → **Status flow**
- "Create an agent" → `agent-factory create` directly
- Single repo project → DO NOT use this Skill
- Monorepo (Nx/Turborepo) → DO NOT use this Skill

## Pre-flight checklist

- Workspace dir exists? If not, `mkdir` first.
- New workspace or existing? → `setup` vs `add`.
- All repo paths absolute? Required — symlinks break with relative paths.
- Always run with `--dry-run` first and show the user the output before executing.

## Security

Write commands (`setup`, `add`, `remove`) perform irreversible filesystem changes:
symlinks, file overwrites (AGENTS.md, CLAUDE.md, settings.json), and `rm -rf` on skill dirs.

**Before any write command:**
1. Run the command with `--dry-run` and show the output to the user.
2. Ask for explicit approval: "Proceed with the above changes?"
3. Only after approval, re-run without `--dry-run`.

Never pass `-y` to `workspace-setup.sh` without prior user approval in the current session.
`agent-factory create` writes files; confirm with the user before invoking.

## Full setup flow

### Step 1: Detect stacks
```
npx @tacuchi/agent-factory detect <repo_path> --json -q
```
Capture JSON. Extract `alias`, `primaryTech`, `stackCsv`, `verifyCommands`.
Use `stackCsv` exactly as returned — pass full value to `--stacks`.

### Step 2: Preview workspace infrastructure (dry-run)
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" setup <workspace_path> <repo1> <repo2> ... \
  --stacks "stackCsv1|stackCsv2|..." --dry-run
```

Show output to user. Ask: "Proceed with these changes?" On approval:
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" setup <workspace_path> <repo1> <repo2> ... \
  --stacks "stackCsv1|stackCsv2|..." -y
```
Creates: dirs, symlinks, settings.json, AGENTS.md, CLAUDE.md, config.

### Step 3: Create specialist agents
Confirm with the user before running. Per repo:
```
npx @tacuchi/agent-factory create \
  --name repo-<alias> --role specialist --scope <repo_path> \
  --output <workspace_path> --target all -q
```
Auto-appends `-agent` suffix: `repo-<alias>` → `repo-<alias>-agent.md`.

### Step 4: Create coordinator agent
Confirm with the user before running.
```
npx @tacuchi/agent-factory create \
  --name coordinator --role coordinator --model opus \
  --specialists "repo-<alias1>-agent,repo-<alias2>-agent,..." \
  --repo-count <N> --output <workspace_path> --target all -q
```
`--specialists` list must use full names with `-agent` suffix.

## Add repo flow

### Step 1: Detect stack
```
npx @tacuchi/agent-factory detect <repo_path> --json -q
```

### Step 2: Preview add (dry-run)
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" add <workspace_path> <repo_path> \
  --alias <alias> --stack-csv "<stackCsv>" --dry-run
```

Show output to user. Ask: "Proceed with these changes?" On approval:
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" add <workspace_path> <repo_path> \
  --alias <alias> --stack-csv "<stackCsv>" -y
```

### Step 3: Create specialist
Confirm with the user before running.
```
npx @tacuchi/agent-factory create \
  --name repo-<alias> --role specialist --scope <repo_path> \
  --output <workspace_path> --target all -q
```

### Step 4: Regenerate coordinator
Get updated specialist list (with `-agent` suffix) from existing symlinks.
Confirm with the user before running.
```
npx @tacuchi/agent-factory create \
  --name coordinator --role coordinator --model opus \
  --specialists "<updated_csv_list_with_agent_suffix>" \
  --repo-count <updated_N> --output <workspace_path> --target all -q
```

## Remove repo flow

### Step 1: Preview removal (dry-run)
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" remove <workspace_path> <alias> --dry-run
```

Show output to user. Ask: "Proceed with these changes?" On approval:
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" remove <workspace_path> <alias> -y
```
Removes: symlink, agent files (.agents/, .claude/agents/, .agents/skills/), regenerates docs.

### Step 2: Regenerate coordinator
Get updated specialist list from remaining symlinks.
Confirm with the user before running.
```
npx @tacuchi/agent-factory create \
  --name coordinator --role coordinator --model opus \
  --specialists "<updated_csv_list>" --repo-count <updated_N> \
  --output <workspace_path> --target all -q
```

## Status flow

```
bash "$SKILL_DIR/scripts/workspace-setup.sh" status <workspace_path>
npx @tacuchi/agent-factory list <workspace_path>
```

## Custom agent flow

To create additional agents (architecture, style, code-review, etc.).
Confirm with the user before running.
```
npx @tacuchi/agent-factory create \
  --name <agent-name> \
  --role custom \
  --description "<short description>" \
  --instructions "<body text or path to .md file>" \
  --model sonnet \
  --output <workspace_path> \
  --target all -q
```

## If detect returns "Generic"

Ask the user: "Stack was not auto-detected for [repo]. What is the main language/framework?"
Then pass `--stack-csv` to the setup/add command so it persists in config.

## Constraints

- Always run `--dry-run` and show output to user before any write command.
- Always confirm with the user before invoking `agent-factory create`.
- Never pass `-y` without explicit user approval in the current session.
- Always use absolute paths — symlinks break with relative.
- Do not modify `settings.json` manually.
- Single repo or monorepo (Nx/Turborepo) → do NOT use this skill.

Replace `$SKILL_DIR` with the absolute path to this skill's directory.

## Agent hierarchy

`coordinator-agent (opus)` → `repo-*-agent (sonnet)` per repo.
Coordinator delegates to specialists via `Task`. Specialists execute autonomously.

## Compatibility

`.claude/agents/*.md` (Claude Code) | `.agents/*.md` (Codex/Gemini/Cursor) | `.agents/skills/*/SKILL.md` (Warp/Codex/Cursor/Gemini CLI) | `AGENTS.md` (20+ tools)
