# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An **Agent Skill** that scaffolds multi-repo workspaces for AI coding agents (Claude Code, Codex, Gemini CLI, Cursor, Warp). It orchestrates two tools:

- **`workspace-setup.sh`** (bundled in `scripts/`) — offline bash script that creates workspace infrastructure: directories, symlinks, `.claude/settings.json`, `AGENTS.md`, `CLAUDE.md`, and persisted config
- **`@tacuchi/agent-factory`** (external npm CLI via `npx`) — detects tech stacks and generates AI agent files in 3 formats (Claude YAML frontmatter, plain markdown, Agent Skills standard)

## Repository structure

```
SKILL.md                              # Skill definition — YAML frontmatter + AI agent instructions
scripts/workspace-setup.sh            # Core bash script (v2.0.0) — 4 commands: setup, add, remove, status
templates/settings.json.tmpl          # Template for .claude/settings.json (additionalDirectories)
templates/workspace-instructions.md.tmpl  # Template for AGENTS.md/CLAUDE.md (Spanish)
```

## Key commands

```bash
# workspace-setup.sh subcommands (always use absolute paths for repos)
bash scripts/workspace-setup.sh setup <workspace> <repo1> <repo2> --stacks "csv1|csv2" -y
bash scripts/workspace-setup.sh add <workspace> <repo> --alias <name> --stack-csv "csv" -y
bash scripts/workspace-setup.sh remove <workspace> <alias> -y
bash scripts/workspace-setup.sh status <workspace>

# Flags: -y (skip confirms), -n/--dry-run (preview), -v/--verbose

# agent-factory (external dependency)
npx @tacuchi/agent-factory detect <repo_path> --json -q
npx @tacuchi/agent-factory create --name <name> --role specialist --scope <path> --output <ws> --target all -y -q
npx @tacuchi/agent-factory list <workspace>
```

There is no build, lint, or test system — this is a shell script + markdown project.

## Architecture details

- `SKILL.md` is the entry point for AI agents. Its YAML frontmatter triggers on phrases like "create workspace", "add repo", etc. The body contains step-by-step flows (Full setup, Add, Remove, Status, Custom agent).
- `workspace-setup.sh` uses a key-value store (`_SK_KEYS`/`_SK_VALS` arrays) to track repo aliases and their stack CSVs in memory, persisted to `.claude/.multirepo-space.conf`.
- Templates use `{{variable}}` placeholder syntax, replaced via bash string substitution in `regenerate_docs()`.
- The script derives aliases from repo directory names: `basename | tr '_.' '-' | cut -c1-30`.
- Config file format: `REPO_<alias>=<absolute_path>|<stackCsv>` — one line per repo.
- `agent-factory` auto-appends `-agent` suffix to names: `repo-frontend` becomes `repo-frontend-agent.md`.

## Conventions

- Workspace templates and docs are in **Spanish**.
- All repo paths must be **absolute** — symlinks break with relative paths.
- The script writes only inside the workspace directory; it makes no network requests and does not modify system files.
- Stacks are passed pipe-separated between repos (`--stacks "csv1|csv2"`) but comma-separated within a single repo's stack CSV.
