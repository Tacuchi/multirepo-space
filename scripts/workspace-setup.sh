#!/usr/bin/env bash
set -euo pipefail

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPL_DIR="$SCRIPT_DIR/templates"

OPT_YES=false
OPT_DRY_RUN=false
OPT_VERBOSE=false

info()  { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }
ok()    { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
verbose() { $OPT_VERBOSE && info "$@"; return 0; }
die() { error "$@"; exit 1; }

_SK_KEYS=()
_SK_VALS=()
_sk_clear() { _SK_KEYS=(); _SK_VALS=(); }
_sk_set() {
  local key="$1" val="$2" i
  for i in "${!_SK_KEYS[@]}"; do
    if [[ "${_SK_KEYS[$i]}" == "$key" ]]; then _SK_VALS[$i]="$val"; return; fi
  done
  _SK_KEYS+=("$key"); _SK_VALS+=("$val")
}
_sk_get() {
  local key="$1" i
  for i in "${!_SK_KEYS[@]}"; do
    if [[ "${_SK_KEYS[$i]}" == "$key" ]]; then printf '%s' "${_SK_VALS[$i]}"; return; fi
  done
}
_sk_del() {
  local key="$1" i; local nk=() nv=()
  for i in "${!_SK_KEYS[@]}"; do
    if [[ "${_SK_KEYS[$i]}" != "$key" ]]; then nk+=("${_SK_KEYS[$i]}"); nv+=("${_SK_VALS[$i]}"); fi
  done
  _SK_KEYS=("${nk[@]+${nk[@]}}"); _SK_VALS=("${nv[@]+${nv[@]}}")
}

confirm() {
  if $OPT_YES; then return 0; fi
  read -rp "${1:-Continue?} [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

write_file() {
  local dest="$1" content="$2"
  if $OPT_DRY_RUN; then info "[dry-run] Would write: $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  echo "$content" > "$dest"
  verbose "Written: $dest"
}

template() {
  local f="$1"
  [[ -f "$f" ]] || die "Template not found: $f"
  cat "$f"
}

derive_alias() {
  basename "$1" | tr '_.' '-' | cut -c1-30
}

save_config() {
  local ws="$1"
  local conf="$ws/.claude/.multirepo-space.conf"
  if $OPT_DRY_RUN; then info "[dry-run] Would save config"; return 0; fi
  mkdir -p "$(dirname "$conf")"
  echo "# workspace-setup config" > "$conf"
  for link in "$ws/repos"/*; do
    [[ -L "$link" ]] || continue
    local a; a=$(basename "$link")
    local p; p=$(readlink "$link")
    local stack_csv; stack_csv=$(_sk_get "$a")
    echo "REPO_${a}=${p}|${stack_csv}" >> "$conf"
  done
  verbose "Saved config: $conf"
}

load_config() {
  local ws="$1"
  local conf="$ws/.claude/.multirepo-space.conf"
  _sk_clear
  if [[ -f "$conf" ]]; then
    while IFS= read -r line; do
      [[ "$line" =~ ^REPO_ ]] || continue
      local key="${line%%=*}"
      local val="${line#*=}"
      local alias="${key#REPO_}"
      local stack_csv="${val#*|}"
      _sk_set "$alias" "$stack_csv"
    done < "$conf"
    verbose "Loaded config from: $conf"
  fi
}

regenerate_docs() {
  local ws="$1"
  local today; today=$(date +%Y-%m-%d)

  local aliases=() paths=() csvs=()
  if [[ -d "$ws/repos" ]]; then
    for link in "$ws/repos"/*; do
      [[ -L "$link" ]] || continue
      local a; a=$(basename "$link")
      local p; p=$(readlink "$link")
      aliases+=("$a"); paths+=("$p")
      local csv; csv=$(_sk_get "$a"); csvs+=("${csv:-Generic}")
    done
  fi

  local N=${#aliases[@]}
  local repos_word="repositorios"; [[ $N -eq 1 ]] && repos_word="repositorio"

  local repos_table="" agents_table=""
  agents_table="| \`coordinator-agent\` | Orquesta trabajo multi-repo, delega a especialistas | Workspace completo |"$'\n'
  for i in "${!aliases[@]}"; do
    repos_table+="| ${aliases[$i]} | ${csvs[$i]} | \`${paths[$i]}\` |"$'\n'
    agents_table+="| \`repo-${aliases[$i]}-agent\` | Especialista ${csvs[$i]%%,*} | Repo $((i+1)) |"$'\n'
  done

  local additional_dirs=""
  for i in "${!paths[@]}"; do
    local comma=""; [[ $i -lt $((N-1)) ]] && comma=","
    additional_dirs+="    \"${paths[$i]}\"${comma}"$'\n'
  done

  local instructions; instructions=$(template "$TMPL_DIR/workspace-instructions.md.tmpl")
  for var in N repos_word repos_table agents_table today; do
    instructions="${instructions//\{\{$var\}\}/${!var}}"
  done
  write_file "$ws/AGENTS.md" "$instructions"
  write_file "$ws/CLAUDE.md" "$instructions"

  local settings; settings=$(template "$TMPL_DIR/settings.json.tmpl")
  settings="${settings//\{\{additional_directories\}\}/$additional_dirs}"
  write_file "$ws/.claude/settings.json" "$settings"

  verbose "Regenerated docs ($N repos)"
}

cmd_setup() {
  local ws="$1"; shift; local repos=("$@")
  ws=$(cd "$ws" && pwd)
  [[ -d "$ws" ]] || die "Workspace path does not exist: $ws"
  for rp in "${repos[@]}"; do [[ -d "$rp" ]] || die "Repo not found: $rp"; done

  if [[ -f "$ws/AGENTS.md" ]]; then
    warn "Workspace already initialized."
    confirm "Overwrite?" || { info "Aborted."; exit 0; }
  fi

  _sk_clear
  local stacks_arr=()
  IFS='|' read -ra stacks_arr <<< "${OPT_STACKS:-}"

  info "Setting up workspace with ${#repos[@]} repos..."

  mkdir -p "$ws/repos" "$ws/docs" "$ws/scripts"
  local idx=0
  for rp in "${repos[@]}"; do
    local abs_rp; abs_rp=$(cd "$rp" && pwd)
    local alias; alias=$(derive_alias "$abs_rp")
    local link="$ws/repos/$alias"
    if $OPT_DRY_RUN; then
      info "[dry-run] Would symlink: $link -> $abs_rp"
    else
      ln -sf "$abs_rp" "$link"
    fi
    _sk_set "$alias" "${stacks_arr[$idx]:-Generic}"
    ((idx++)) || true
  done

  write_file "$ws/docs/.gitkeep" ""
  write_file "$ws/scripts/.gitkeep" ""

  regenerate_docs "$ws"
  save_config "$ws"

  if $OPT_DRY_RUN; then
    ok "Dry-run complete."
  else
    ok "Workspace created! Run agent-factory to generate agents."
  fi
}

cmd_add() {
  local ws="$1" rp="$2"
  ws=$(cd "$ws" && pwd); rp=$(cd "$rp" && pwd)
  [[ -f "$ws/AGENTS.md" ]] || die "Not a workspace: $ws"

  load_config "$ws"

  local alias="${OPT_ALIAS:-$(derive_alias "$rp")}"
  if [[ -L "$ws/repos/$alias" ]]; then
    local s=2; while [[ -L "$ws/repos/${alias}-${s}" ]]; do ((s++)); done
    warn "Alias '$alias' exists, using '${alias}-${s}'"
    alias="${alias}-${s}"
  fi

  info "Adding repo: $alias"
  confirm "Add '$alias'?" || { info "Aborted."; exit 0; }

  if ! $OPT_DRY_RUN; then
    mkdir -p "$ws/repos"
    ln -s "$rp" "$ws/repos/$alias"
  fi

  _sk_set "$alias" "${OPT_STACK_CSV:-Generic}"
  regenerate_docs "$ws"
  save_config "$ws"
  ok "Repo '$alias' added."
}

cmd_remove() {
  local ws="$1" alias="$2"
  ws=$(cd "$ws" && pwd)
  [[ -f "$ws/AGENTS.md" ]] || die "Not a workspace: $ws"

  confirm "Remove '$alias'?" || { info "Aborted."; exit 0; }

  for dir in ".agents" ".claude/agents"; do
    local f="$ws/$dir/repo-${alias}-agent.md"
    if [[ -f "$f" ]]; then
      if $OPT_DRY_RUN; then info "[dry-run] Would remove: $f"
      else rm "$f"; verbose "Removed: $f"; fi
    fi
  done
  local skill_dir="$ws/.agents/skills/repo-${alias}-agent"
  if [[ -d "$skill_dir" ]]; then
    if $OPT_DRY_RUN; then info "[dry-run] Would remove: $skill_dir"
    else rm -rf "$skill_dir"; verbose "Removed: $skill_dir"; fi
  fi

  local link="$ws/repos/$alias"
  if [[ -L "$link" ]]; then
    if $OPT_DRY_RUN; then info "[dry-run] Would remove symlink: $link"
    else rm "$link"; fi
  fi

  load_config "$ws"
  _sk_del "$alias"
  regenerate_docs "$ws"
  save_config "$ws"
  ok "Repo '$alias' removed."
}

cmd_status() {
  local ws="$1"
  ws=$(cd "$ws" && pwd)
  [[ -f "$ws/AGENTS.md" ]] || die "Not a workspace: $ws"

  load_config "$ws"
  echo ""
  info "Workspace: $(basename "$ws") ($ws)"
  echo ""

  local total=0 healthy=0 broken=0
  if [[ -d "$ws/repos" ]]; then
    printf "  %-25s %-10s %s\n" "Alias" "Status" "Target"
    printf "  %-25s %-10s %s\n" "-------------------------" "----------" "--------------------"
    for link in "$ws/repos"/*; do
      [[ -L "$link" ]] || continue
      ((total++))
      local a; a=$(basename "$link")
      local t; t=$(readlink "$link")
      if [[ -d "$t" ]]; then
        printf "  %-25s \033[32m%-10s\033[0m %s\n" "$a" "OK" "$t"
        ((healthy++))
      else
        printf "  %-25s \033[31m%-10s\033[0m %s\n" "$a" "BROKEN" "$t"
        ((broken++))
      fi
    done
  fi

  echo ""
  local agents_n=0 claude_n=0 skills_n=0
  [[ -d "$ws/.agents" ]] && agents_n=$(find "$ws/.agents" -maxdepth 1 -name "*-agent.md" | wc -l | xargs)
  [[ -d "$ws/.claude/agents" ]] && claude_n=$(find "$ws/.claude/agents" -maxdepth 1 -name "*-agent.md" | wc -l | xargs)
  [[ -d "$ws/.agents/skills" ]] && skills_n=$(find "$ws/.agents/skills" -maxdepth 1 -type d -name "*-agent" | wc -l | xargs)
  local parity="OK"
  [[ "$agents_n" != "$claude_n" || "$agents_n" != "$skills_n" ]] && parity="MISMATCH" || true

  info "Repos: $total (healthy: $healthy, broken: $broken)"
  info "Agents: .agents/=$agents_n, .claude/agents/=$claude_n, skills/=$skills_n ($parity)"
  info "AGENTS.md $([ -f "$ws/AGENTS.md" ] && echo "EXISTS" || echo "MISSING")"
  info "CLAUDE.md $([ -f "$ws/CLAUDE.md" ] && echo "EXISTS" || echo "MISSING")"
  info "settings.json $([ -f "$ws/.claude/settings.json" ] && echo "EXISTS" || echo "MISSING")"
}

usage() {
  cat <<EOF
workspace-setup v$VERSION - Workspace infrastructure for multi-repo AI workspaces

Usage: workspace-setup.sh <command> [options] <args>

Commands:
  setup   <ws> <repo1> [repo2...]   Scaffold workspace infrastructure
  add     <ws> <repo>               Add repo to workspace
  remove  <ws> <alias>              Remove repo from workspace
  status  <ws>                      Check workspace health

Options:
  -y, --yes                  Skip confirmations
  -n, --dry-run              Preview without writing
  -v, --verbose              Detailed output
  --stacks "s1|s2|..."       Stack CSVs (pipe-separated, for setup)
  --alias NAME               Override alias (for add)
  --stack-csv "CSV"          Stack CSV string (for add)
EOF
}

OPT_STACKS="" OPT_ALIAS="" OPT_STACK_CSV=""
main() {
  local cmd="" args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)     OPT_YES=true ;;
      -n|--dry-run) OPT_DRY_RUN=true ;;
      -v|--verbose) OPT_VERBOSE=true ;;
      -h|--help)    usage; exit 0 ;;
      --version)    echo "workspace-setup v$VERSION"; exit 0 ;;
      --stacks)     shift; OPT_STACKS="$1" ;;
      --stacks=*)   OPT_STACKS="${1#*=}" ;;
      --alias)      shift; OPT_ALIAS="$1" ;;
      --alias=*)    OPT_ALIAS="${1#*=}" ;;
      --stack-csv)  shift; OPT_STACK_CSV="$1" ;;
      --stack-csv=*)OPT_STACK_CSV="${1#*=}" ;;
      *) if [[ -z "$cmd" ]]; then cmd="$1"; else args+=("$1"); fi ;;
    esac
    shift
  done

  case "$cmd" in
    setup)  [[ ${#args[@]} -lt 2 ]] && die "Usage: workspace-setup.sh setup <ws> <repo1> [repo2...]"; cmd_setup "${args[@]}" ;;
    add)    [[ ${#args[@]} -ne 2 ]] && die "Usage: workspace-setup.sh add <ws> <repo>"; cmd_add "${args[@]}" ;;
    remove) [[ ${#args[@]} -ne 2 ]] && die "Usage: workspace-setup.sh remove <ws> <alias>"; cmd_remove "${args[@]}" ;;
    status) [[ ${#args[@]} -ne 1 ]] && die "Usage: workspace-setup.sh status <ws>"; cmd_status "${args[@]}" ;;
    *)      usage; exit 1 ;;
  esac
}

main "$@"
