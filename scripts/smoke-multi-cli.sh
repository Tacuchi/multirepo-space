#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$ROOT_DIR/scripts/workspace-setup.sh"
AGENT_FACTORY_BIN="${AGENT_FACTORY_BIN:-/Users/tacuchi/Git/agent-factory/bin/agent-factory.js}"

fail() { echo "[FAIL] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }

assert_file() {
  local f="$1"
  [[ -f "$f" ]] || fail "Missing file: $f"
}

assert_contains() {
  local f="$1" text="$2"
  grep -Fq "$text" "$f" || fail "Expected '$text' in $f"
}

[[ -x "$SETUP_SCRIPT" ]] || fail "workspace-setup.sh not executable: $SETUP_SCRIPT"
[[ -f "$AGENT_FACTORY_BIN" ]] || fail "agent-factory bin not found: $AGENT_FACTORY_BIN"

TMP_ROOT="$(mktemp -d /tmp/multirepo-smoke-XXXXXX)"
WORKSPACE="$TMP_ROOT/workspace"
REPO_A="$TMP_ROOT/repo-frontend"
REPO_B="$TMP_ROOT/repo-backend"

trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$WORKSPACE" "$REPO_A" "$REPO_B"

cat > "$REPO_A/package.json" <<'JSON'
{
  "name": "repo-frontend",
  "version": "1.0.0",
  "bin": {
    "repo-frontend": "bin/cli.js"
  }
}
JSON

echo '#!/usr/bin/env bash' > "$REPO_B/deploy.sh"
echo 'echo backend' >> "$REPO_B/deploy.sh"

info "Scaffolding workspace"
bash "$SETUP_SCRIPT" setup "$WORKSPACE" "$REPO_A" "$REPO_B" --stacks "Node.js,CLI|Bash,Shell" -y >/dev/null

info "Generating specialist + coordinator agents with target=all"
node "$AGENT_FACTORY_BIN" create \
  --name repo-frontend \
  --role specialist \
  --scope "$REPO_A" \
  --stack "Node.js,CLI" \
  --output "$WORKSPACE" \
  --target all \
  -y >/dev/null

node "$AGENT_FACTORY_BIN" create \
  --name repo-backend \
  --role specialist \
  --scope "$REPO_B" \
  --stack "Bash,Shell" \
  --output "$WORKSPACE" \
  --target all \
  -y >/dev/null

node "$AGENT_FACTORY_BIN" create \
  --name coordinator \
  --role coordinator \
  --model opus \
  --specialists "repo-frontend-agent,repo-backend-agent" \
  --repo-count 2 \
  --output "$WORKSPACE" \
  --target all \
  -y >/dev/null

info "Validating generated files"
assert_file "$WORKSPACE/AGENTS.md"
assert_file "$WORKSPACE/CLAUDE.md"

assert_file "$WORKSPACE/.claude/agents/repo-frontend-agent.md"
assert_file "$WORKSPACE/.claude/agents/repo-backend-agent.md"
assert_file "$WORKSPACE/.claude/agents/coordinator-agent.md"

assert_file "$WORKSPACE/.agents/repo-frontend-agent.md"
assert_file "$WORKSPACE/.agents/repo-backend-agent.md"
assert_file "$WORKSPACE/.agents/coordinator-agent.md"

assert_file "$WORKSPACE/.agents/skills/repo-frontend-agent/SKILL.md"
assert_file "$WORKSPACE/.agents/skills/repo-backend-agent/SKILL.md"
assert_file "$WORKSPACE/.agents/skills/coordinator-agent/SKILL.md"

assert_file "$WORKSPACE/.gemini/agents/repo-frontend-agent.md"
assert_file "$WORKSPACE/.gemini/agents/repo-backend-agent.md"
assert_file "$WORKSPACE/.gemini/agents/coordinator-agent.md"

assert_file "$WORKSPACE/.opencode.json"
assert_file "$WORKSPACE/.crush.json"
assert_file "$WORKSPACE/docs/warp-oz/environment-example.md"

info "Validating orchestration semantics"
assert_contains "$WORKSPACE/.agents/coordinator-agent.md" 'repo-frontend-agent'
assert_contains "$WORKSPACE/.agents/coordinator-agent.md" 'repo-backend-agent'
assert_contains "$WORKSPACE/.agents/repo-frontend-agent.md" "$REPO_A"
assert_contains "$WORKSPACE/.agents/repo-backend-agent.md" "$REPO_B"

ok "Smoke test passed (workspace: $WORKSPACE)"
