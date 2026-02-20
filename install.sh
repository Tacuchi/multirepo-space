#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$REPO_DIR/scripts"

info()  { echo -e "\033[1;34m[info]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[ok]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[warn]\033[0m $*"; }

SKILL_DIRS=(
  "$HOME/.claude/skills/multirepo-space"
  "$HOME/.agents/skills/multirepo-space"
  "$HOME/.codex/skills/multirepo-space"
  "$HOME/.cursor/skills/multirepo-space"
  "$HOME/.gemini/skills/multirepo-space"
)

OLD_SKILL_DIRS=(
  "$HOME/.claude/skills/hub-setup"
  "$HOME/.agents/skills/hub-setup"
  "$HOME/.codex/skills/hub-setup"
  "$HOME/.cursor/skills/hub-setup"
  "$HOME/.gemini/skills/hub-setup"
)

echo ""
info "Installing multirepo-space..."
echo ""

# 1. Add to PATH
add_to_path() {
  local shell_rc="$1"
  local path_line="export PATH=\"$SCRIPTS_DIR:\$PATH\""

  if [[ -f "$shell_rc" ]]; then
    if ! grep -q "multirepo-space" "$shell_rc"; then
      echo "" >> "$shell_rc"
      echo "# multirepo-space CLI" >> "$shell_rc"
      echo "$path_line" >> "$shell_rc"
      ok "Added to PATH in $shell_rc"
    else
      info "PATH already configured in $shell_rc"
    fi
  fi
}

if [[ -f "$HOME/.zshrc" ]]; then
  add_to_path "$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
  add_to_path "$HOME/.bashrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
  add_to_path "$HOME/.bash_profile"
else
  warn "Could not find shell rc file. Add manually: export PATH=\"$SCRIPTS_DIR:\$PATH\""
fi

# 2. Create symlinks
for skill_dir in "${SKILL_DIRS[@]}"; do
  parent_dir=$(dirname "$skill_dir")
  if [[ -d "$parent_dir" ]] || [[ "$parent_dir" == *"/.claude/skills"* ]] || [[ "$parent_dir" == *"/.agents/skills"* ]]; then
    mkdir -p "$parent_dir"

    if [[ -L "$skill_dir" ]]; then
      current_target=$(readlink "$skill_dir")
      if [[ "$current_target" == "$REPO_DIR" ]]; then
        info "Symlink already correct: $skill_dir"
        continue
      fi
      rm "$skill_dir"
    elif [[ -d "$skill_dir" ]]; then
      warn "Removing old non-symlink directory: $skill_dir"
      rm -rf "$skill_dir"
    fi

    ln -s "$REPO_DIR" "$skill_dir"
    ok "Symlink: $skill_dir -> $REPO_DIR"
  fi
done

# 3. Cleanup old hub-setup skills
for old_dir in "${OLD_SKILL_DIRS[@]}"; do
  if [[ -d "$old_dir" ]] || [[ -L "$old_dir" ]]; then
    rm -rf "$old_dir"
    ok "Removed old skill: $old_dir"
  fi
done

echo ""
ok "Installation complete!"
info "Restart your shell or run: source ~/.zshrc"
info "Then try: multirepo-space --help"
