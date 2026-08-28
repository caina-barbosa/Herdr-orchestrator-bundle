#!/usr/bin/env bash
# Static and load-time checks for the shareable bundle.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

required=(
  package.json
  README.md
  extensions/orchestrator-idle-handoff.ts
  optional/auto-resume-after-compaction.ts
  skills/herdr-orchestrator/SKILL.md
  skills/herdr-orchestrator/scripts/herdr-watchdog
  scripts/install.sh
)
for path in "${required[@]}"; do
  [[ -f "$path" ]] || { echo "missing: $path" >&2; exit 1; }
done

bash -n skills/herdr-orchestrator/scripts/herdr-watchdog
bash -n scripts/install.sh
[[ -x skills/herdr-orchestrator/scripts/herdr-watchdog ]] || {
  echo "watchdog is not executable" >&2
  exit 1
}
[[ -x scripts/install.sh ]] || {
  echo "installer is not executable" >&2
  exit 1
}

jq -e '
  .private == true and
  .pi.extensions == ["./extensions/orchestrator-idle-handoff.ts"] and
  .pi.skills == ["./skills"]
' package.json >/dev/null
if jq -e '.pi.extensions[] | contains("auto-resume")' package.json >/dev/null; then
  echo "optional auto-resume extension must not be enabled by the package manifest" >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
p = Path("skills/herdr-orchestrator/SKILL.md")
text = p.read_text()
assert text.startswith("---\n"), "SKILL.md is missing YAML frontmatter"
frontmatter = text.split("---\n", 2)[1]
assert "name: herdr-orchestrator" in frontmatter
assert "description:" in frontmatter
PY

rg -q 'PI_ORCHESTRATOR_PARENT' extensions/orchestrator-idle-handoff.ts
rg -q 'subagent:result-intercom' extensions/orchestrator-idle-handoff.ts
rg -q 'event.reason !== "threshold"' optional/auto-resume-after-compaction.ts
rg -q -- '--prefix is required' skills/herdr-orchestrator/scripts/herdr-watchdog

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck skills/herdr-orchestrator/scripts/herdr-watchdog scripts/install.sh
else
  echo "note: shellcheck not installed; skipped" >&2
fi

# Pi's TypeScript loader parses both extensions without making a model request.
if command -v pi >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  PI_CODING_AGENT_DIR="$tmp" pi \
    --no-extensions --no-skills \
    -e "$root/extensions/orchestrator-idle-handoff.ts" \
    -e "$root/optional/auto-resume-after-compaction.ts" \
    --list-models '__herdr_bundle_no_match__' >/dev/null
fi

printf 'bundle checks passed\n'
