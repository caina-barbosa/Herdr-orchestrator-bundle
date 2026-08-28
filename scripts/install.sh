#!/usr/bin/env bash
# Install the bundle into Pi's global user resource directories.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [--with-auto-resume] [--force]

  --with-auto-resume  Also install the optional threshold-compaction resume extension.
  --force             Back up and replace conflicting installed files.
  -h, --help          Show this help.

pi-intercom is a required runtime dependency but is deliberately installed
separately. Run: pi install npm:pi-intercom@0.9.2
EOF
}

with_auto_resume=0
force=0
while (($#)); do
  case "$1" in
    --with-auto-resume) with_auto_resume=1 ;;
    --force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
agent_dir=${PI_CODING_AGENT_DIR:-"$HOME/.pi/agent"}
skill_dir="$agent_dir/skills/herdr-orchestrator"
ext_dir="$agent_dir/extensions"
bin_dir="$HOME/.local/bin"
backup_dir="$agent_dir/backups/herdr-orchestrator-bundle-$(date +%Y%m%d-%H%M%S)"

missing=()
for command_name in pi herdr jq md5sum date; do
  command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
done
if ((${#missing[@]})); then
  printf 'Missing required command(s): %s\n' "${missing[*]}" >&2
  exit 1
fi
if ((BASH_VERSINFO[0] < 4)); then
  echo "herdr-watchdog requires Bash 4 or newer (found $BASH_VERSION)." >&2
  exit 1
fi
if ! date -d '2024-01-01T00:00:00Z' +%s >/dev/null 2>&1; then
  echo "herdr-watchdog requires GNU date (date -d support)." >&2
  exit 1
fi

backup_conflict() {
  local destination=$1 source=$2 relative=${1#"$agent_dir"/}
  if [[ ! -e "$destination" && ! -L "$destination" ]]; then
    return
  fi
  if [[ -f "$destination" && -f "$source" ]] && cmp -s "$destination" "$source"; then
    return
  fi
  if ((force == 0)); then
    echo "Refusing to overwrite $destination; rerun with --force to back it up first." >&2
    exit 1
  fi
  mkdir -p "$backup_dir/$(dirname "$relative")"
  cp -a "$destination" "$backup_dir/$relative"
  rm -rf "$destination"
}

install_file() {
  local source=$1 destination=$2 mode=$3
  backup_conflict "$destination" "$source"
  install -D -m "$mode" "$source" "$destination"
  printf 'installed %s\n' "$destination"
}

mkdir -p "$skill_dir/scripts" "$ext_dir" "$bin_dir"
install_file "$root/skills/herdr-orchestrator/SKILL.md" "$skill_dir/SKILL.md" 0644
install_file "$root/skills/herdr-orchestrator/scripts/herdr-watchdog" "$skill_dir/scripts/herdr-watchdog" 0755
install_file "$root/extensions/orchestrator-idle-handoff.ts" "$ext_dir/orchestrator-idle-handoff.ts" 0644

if ((with_auto_resume)); then
  install_file "$root/optional/auto-resume-after-compaction.ts" "$ext_dir/auto-resume-after-compaction.ts" 0644
fi

watchdog_link="$bin_dir/herdr-watchdog"
if [[ -e "$watchdog_link" || -L "$watchdog_link" ]]; then
  current_target=$(readlink -f "$watchdog_link" 2>/dev/null || true)
  wanted_target=$(readlink -f "$skill_dir/scripts/herdr-watchdog")
  if [[ "$current_target" != "$wanted_target" ]]; then
    if ((force == 0)); then
      echo "Refusing to replace $watchdog_link; rerun with --force." >&2
      exit 1
    fi
    mkdir -p "$backup_dir/bin"
    cp -a "$watchdog_link" "$backup_dir/bin/herdr-watchdog"
    rm -f "$watchdog_link"
  fi
fi
ln -sfn "$skill_dir/scripts/herdr-watchdog" "$watchdog_link"
printf 'linked    %s -> %s\n' "$watchdog_link" "$skill_dir/scripts/herdr-watchdog"

if ! pi list 2>/dev/null | grep -q 'pi-intercom'; then
  cat >&2 <<'EOF'

WARNING: pi-intercom was not found in `pi list`.
Install the tested dependency before use:
  pi install npm:pi-intercom@0.9.2
EOF
fi

if [[ -d "$backup_dir" ]]; then
  printf 'backups   %s\n' "$backup_dir"
fi
if [[ :$PATH: != *":$bin_dir:"* ]]; then
  printf '\nAdd %s to PATH so `herdr-watchdog` is directly callable.\n' "$bin_dir"
fi
cat <<EOF

Installation complete.
- Restart every Pi session that will participate, or run /reload in each one.
- Launch Pi from inside Herdr so HERDR_ENV=1 is present.
- Verify with: $root/scripts/check-bundle.sh
EOF
