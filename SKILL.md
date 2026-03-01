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
- First time? Suggest `--dry-run` to preview.

## Full setup flow

### Step 1: Detect stacks
```
npx @tacuchi/agent-factory detect <repo_path> --json -q
```
Capture JSON. Extract `alias`, `primaryTech`, `stackCsv`, `verifyCommands`.
Use `stackCsv` exactly as returned — pass full value to `--stacks`.

### Step 2: Create workspace infrastructure
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" setup <workspace_path> <repo1> <repo2> ... \
  --stacks "stackCsv1|stackCsv2|..." -y
```
Creates: dirs, symlinks, settings.json, AGENTS.md, CLAUDE.md, config.

### Step 3: Create specialist agents
Per repo:
```
npx @tacuchi/agent-factory create \
  --name repo-<alias> --role specialist --scope <repo_path> \
  --output <workspace_path> --target all -y -q
```
Auto-appends `-agent` suffix: `repo-<alias>` → `repo-<alias>-agent.md`.

### Step 4: Create coordinator agent
```
npx @tacuchi/agent-factory create \
  --name coordinator --role coordinator --model opus \
  --specialists "repo-<alias1>-agent,repo-<alias2>-agent,..." \
  --repo-count <N> --output <workspace_path> --target all -y -q
```
`--specialists` list must use full names with `-agent` suffix.

## Add repo flow

### Step 1: Detect stack
```
npx @tacuchi/agent-factory detect <repo_path> --json -q
```

### Step 2: Add to workspace
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" add <workspace_path> <repo_path> \
  --alias <alias> --stack-csv "<stackCsv>" -y
```

### Step 3: Create specialist
```
npx @tacuchi/agent-factory create \
  --name repo-<alias> --role specialist --scope <repo_path> \
  --output <workspace_path> --target all -y -q
```

### Step 4: Regenerate coordinator
Get updated specialist list (with `-agent` suffix) from existing symlinks:
```
npx @tacuchi/agent-factory create \
  --name coordinator --role coordinator --model opus \
  --specialists "<updated_csv_list_with_agent_suffix>" \
  --repo-count <updated_N> --output <workspace_path> --target all -y -q
```

## Remove repo flow

### Step 1: Remove infrastructure + agent files
```
bash "$SKILL_DIR/scripts/workspace-setup.sh" remove <workspace_path> <alias> -y
```
Removes: symlink, agent files (.agents/, .claude/agents/, .agents/skills/), regenerates docs.

### Step 2: Regenerate coordinator
Get updated specialist list from remaining symlinks:
```
npx @tacuchi/agent-factory create \
  --name coordinator --role coordinator --model opus \
  --specialists "<updated_csv_list>" --repo-count <updated_N> \
  --output <workspace_path> --target all -y -q
```

## Status flow

```
bash "$SKILL_DIR/scripts/workspace-setup.sh" status <workspace_path>
npx @tacuchi/agent-factory list <workspace_path>
```

## Custom agent flow

To create additional agents (architecture, style, code-review, etc.):
```
npx @tacuchi/agent-factory create \
  --name <agent-name> \
  --role custom \
  --description "<short description>" \
  --instructions "<body text or path to .md file>" \
  --model sonnet \
  --output <workspace_path> \
  --target all -y -q
```

## If detect returns "Generic"

Ask the user: "Stack was not auto-detected for [repo]. What is the main language/framework?"
Then pass `--stack-csv` to the setup/add command so it persists in config.

## Constraints

- Single repo or monorepo (Nx/Turborepo) → do NOT use this skill.
- Never run setup on populated workspace without user confirmation.
- Always use absolute paths — symlinks break with relative.
- Suggest `--dry-run` for first-time users.
- Do not modify `settings.json` manually.

Replace `$SKILL_DIR` with the absolute path to this skill's directory.

## Agent hierarchy

`coordinator-agent (opus)` → `repo-*-agent (sonnet)` per repo.
Coordinator delegates to specialists via `Task`. Specialists execute autonomously.

## Compatibility

`.claude/agents/*.md` (Claude Code) | `.agents/*.md` (Codex/Gemini/Cursor) | `.agents/skills/*/SKILL.md` (Warp/Codex/Cursor/Gemini CLI) | `AGENTS.md` (20+ tools)
