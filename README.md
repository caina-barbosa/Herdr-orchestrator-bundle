# Herdr Orchestrator Bundle

A shareable Pi package for running a **main orchestrator** and multiple real, visible Pi child sessions in [Herdr](https://herdr.dev/).

The pack combines:

- the `herdr-orchestrator` skill, which defines the orchestration protocol;
- `herdr-watchdog`, which detects stalled or unexpectedly closed children;
- `orchestrator-idle-handoff.ts`, which sends a child's final response back to main through `pi-intercom`; and
- `auto-resume-after-compaction.ts`, an **optional** quality-of-life extension that resumes work after automatic threshold compaction.

The optional auto-resume extension is useful for long-running agents, but the orchestration system does not require it.

## Contents

```text
.
├── extensions/
│   └── orchestrator-idle-handoff.ts       # required; enabled by package manifest
├── optional/
│   └── auto-resume-after-compaction.ts    # optional; not enabled by default
├── skills/
│   └── herdr-orchestrator/
│       ├── SKILL.md
│       └── scripts/
│           └── herdr-watchdog
├── scripts/
│   ├── check-bundle.sh
│   └── install.sh
├── package.json
└── README.md
```

## Architecture

```text
main Pi session
  ├─ loads herdr-orchestrator skill
  ├─ launches named Pi children in Herdr panes/worktrees
  ├─ receives child completions through pi-intercom
  └─ receives watchdog alerts in its own turn

child Pi session
  ├─ starts with PI_ORCHESTRATOR_PARENT=<main intercom name/id>
  ├─ performs one bounded slice
  └─ idle-handoff extension emits the final assistant text to pi-intercom

watchdog pane
  └─ polls Herdr for all child names matching one run-specific prefix
```

`pi-intercom` is a separate runtime dependency. It provides the local broker and consumes the `subagent:result-intercom` event emitted by the idle-handoff extension.

## Requirements

Known-good versions used to assemble this pack:

- Herdr `0.8.2`
- Pi `0.83.0`
- `pi-intercom` `0.9.2`

Required commands:

- `herdr`
- `pi`
- `git`
- `jq`
- Bash 4+
- GNU `date` (`date -d`)
- `md5sum`

### Platform note

The bundled watchdog is currently **Linux-oriented**. It uses Bash associative arrays, GNU `date`, and `md5sum`.

On macOS, install modern Bash, GNU coreutils, and jq, then ensure the GNU utilities precede the system utilities on `PATH`:

```bash
brew install bash coreutils jq
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$(brew --prefix bash)/bin:$PATH"
```

Run `scripts/check-bundle.sh` before relying on the pack on a new platform.

## Install

Because this repository starts private, the recipient must first be added as a GitHub collaborator and authenticate GitHub CLI or SSH.

### 1. Install Herdr

Linux and macOS:

```bash
curl -fsSL https://herdr.dev/install.sh | sh
herdr --version
```

See the official [Herdr installation guide](https://herdr.dev/docs/install/) for Homebrew, mise, Nix, Windows, or manual downloads.

### 2. Install `pi-intercom`

```bash
pi install npm:pi-intercom@0.9.2
```

Restart Pi after installation. Every main and child Pi session must load `pi-intercom`.

### 3. Install this Pi package

#### Option A: install directly from the private Git repository

With SSH configured:

```bash
pi install git:git@github.com:caina-barbosa/Herdr-orchestrator-bundle.git
```

Or with GitHub CLI's HTTPS credential helper:

```bash
gh auth login
gh auth setup-git
pi install git:https://github.com/caina-barbosa/Herdr-orchestrator-bundle.git
```

The package manifest enables the required idle-handoff extension and the skill. It deliberately excludes the optional auto-resume extension.

The watchdog remains inside the skill's `scripts/` directory. The skill can run it by its resolved path even when `herdr-watchdog` is not globally on `PATH`.

#### Option B: clone and run the local installer

This also links `herdr-watchdog` into `~/.local/bin`:

```bash
git clone git@github.com:caina-barbosa/Herdr-orchestrator-bundle.git
cd Herdr-orchestrator-bundle
./scripts/install.sh
```

The installer:

- copies the skill into `${PI_CODING_AGENT_DIR:-~/.pi/agent}/skills/`;
- copies the required extension into `${PI_CODING_AGENT_DIR:-~/.pi/agent}/extensions/`;
- links the watchdog into `~/.local/bin/herdr-watchdog`;
- refuses to overwrite conflicting files unless `--force` is supplied; and
- backs up replaced files under the Pi agent directory when `--force` is used.

Do not use both package installation and copied installation at the same time; that can load duplicate resources.

### 4. Optional: enable auto-resume after compaction

This is recommended for agents expected to work through long contexts, but it is **not required**.

With the local installer:

```bash
./scripts/install.sh --with-auto-resume
```

Or copy it manually:

```bash
mkdir -p "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions"
cp optional/auto-resume-after-compaction.ts \
  "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/"
```

Then restart each Pi session or run `/reload` in it.

### What optional auto-resume does

When Pi emits `session_compact` with reason `threshold`, the extension queues a follow-up message telling the agent to inspect its compacted context and continue doing the work. It does **not** run after manual compaction or overflow-recovery compaction.

Why it is useful:

- a long implementation is less likely to stop merely because threshold compaction ended the current run;
- child sessions can continue toward their slice outcome without a manual nudge.

Why it is optional:

- it can trigger additional model work, tool use, and cost after compaction;
- some users prefer to inspect the compacted state before allowing an agent to continue;
- it is not involved in watchdog monitoring or idle handoff.

## Verify the installation

From a clone of this repository:

```bash
./scripts/check-bundle.sh
```

The check verifies the package manifest, skill frontmatter, executable bits, Bash syntax, required extension markers, and Pi's ability to parse both TypeScript extensions without making a model request. If `shellcheck` is installed, it runs that too.

Check the runtime prerequisites:

```bash
herdr --version
pi --version
jq --version
pi list | grep -E 'pi-intercom|Herdr-orchestrator-bundle|herdr-orchestrator'
```

Inside a Herdr pane:

```bash
test "${HERDR_ENV:-}" = 1 && echo "inside Herdr"
```

If that check fails, exit the terminal, launch or attach to Herdr with `herdr`, and start Pi inside a Herdr pane. Do not start a nested Herdr client from an existing Herdr pane.

## Use the pack

### 1. Start main inside Herdr

From a normal terminal:

```bash
cd /path/to/repository
herdr
```

Then start and name the main Pi session in a Herdr pane:

```bash
pi --name my-main
```

The exact Pi flags and model are your choice.

### 2. Invoke the skill

In main, explicitly invoke the skill or ask Pi to orchestrate approved slices with Herdr:

```text
/skill:herdr-orchestrator Implement the approved slices in PLAN.md.
```

The skill will require a concrete authorized outcome, non-goals, dependencies, ownership boundaries, and proof commands. It launches real Pi processes in separate Herdr panes, not Pi subagents or workflow children.

### 3. Let the orchestrator manage the run

The protocol in `SKILL.md` makes main:

1. verify `HERDR_ENV=1`;
2. get its own intercom target;
3. choose a unique run callsign/prefix;
4. start one watchdog pane;
5. create child panes or Herdr-owned Git worktrees without stealing user focus;
6. inject `PI_ORCHESTRATOR_PARENT=<main>` **before** starting each child Pi process;
7. prompt each child with a bounded slice contract;
8. receive the child's completion through idle handoff;
9. independently review and integrate checkpoints; and
10. acknowledge child closure, remove worktrees/branches, and close the watchdog last.

The default model names in `SKILL.md` are opinionated. Tell the orchestrator your own role-to-model map, or edit the defaults, if those providers/models are unavailable. The user's role map wins.

## How idle handoff works

`extensions/orchestrator-idle-handoff.ts` is inert unless the Pi process starts with:

```bash
PI_ORCHESTRATOR_PARENT=<main-name-or-intercom-id>
```

For an opted-in child, the extension:

1. records the last assistant text when `agent_end` fires;
2. waits for the run to settle;
3. waits one second to avoid racing retries or queued messages;
4. confirms the child is idle and has no pending messages;
5. formats a message beginning with `<child> is idle.`; and
6. emits `subagent:result-intercom` to the shared Pi event bus.

`pi-intercom` receives that event and relays the handoff to main. The handoff also carries the child name, parent target, session-file path, observation time, and context usage for compatible formatters.

Important consequences:

- setting `PI_ORCHESTRATOR_PARENT` after Pi starts is too late;
- every participating Pi process must load the extension and `pi-intercom`;
- unnamed sessions work, but explicit unique names are much easier to operate safely;
- the extension sends only the final assistant text, not every tool result;
- no parent environment variable means no handoff behavior.

## How the watchdog works

Start one watchdog per orchestration run. It dynamically discovers children by a unique name prefix, so later phases can add children without restarting the watchdog.

Canonical form:

```bash
herdr-watchdog <main-target> --prefix <callsign-prefix> \
  [--interval 60] [--threshold 180]
```

The skill normally creates a thin pane below main and runs the command there. Its watch loop:

1. calls `herdr agent list` every `--interval` seconds;
2. selects live agents whose names begin with `--prefix`, excluding main;
3. tracks each child from the first poll onward;
4. considers the child alive when Herdr reports `working` **or** the last 15 visible terminal lines change;
5. alerts once when neither signal changes for `--threshold` seconds;
6. re-arms that child's stall alert if work or screen movement resumes; and
7. alerts if a previously seen child disappears without an acknowledged close.

A stall alert does two things:

- displays a Herdr desktop notification; and
- prompts main with a `WATCHDOG:` message.

When possible, the prompt includes the last three entries from the child's local Pi JSONL session log, a staleness estimate, pane ID, and working directory. This helps main diagnose a question dialog, failed tool call, context issue, or dead process without first polling the pane manually.

### Why check both status and screen movement?

Herdr may briefly report Pi as `idle` while it is visibly streaming or updating. Treating terminal movement as liveness reduces false positives. Conversely, a child blocked in a question UI may remain `idle` with a frozen screen; the watchdog catches that case after the threshold.

### Why acknowledged close matters

Closing a child with plain `herdr pane close` looks identical to a crash from the watcher. Instead use:

```bash
herdr-watchdog close <child-name>
```

Close mode writes a short-lived acknowledgement under `/tmp/herdr-watchdog-acks/` and then closes the child's pane. On the next poll, watch mode consumes the acknowledgement and suppresses the disappearance alert.

For worktree children, remove the Herdr-owned worktree **before** closing its final pane, as described in `SKILL.md`.

### The quoting rule

The main pane ID must expand in main's shell when starting the watcher:

```bash
herdr pane run <watchdog-pane> \
  "herdr-watchdog $HERDR_PANE_ID --prefix run123- --interval 60 --threshold 180"
```

The double quotes are intentional. With single quotes, `$HERDR_PANE_ID` expands in the watchdog pane instead, causing alerts to target the wrong pane.

### Tuning

- `--interval 60` controls polling frequency.
- `--threshold 180` controls the frozen duration before the first alert.
- Use a threshold comfortably larger than the interval.
- Increase the threshold for children that run long commands with static terminal output and imperfect Herdr lifecycle status.
- Always use a unique callsign prefix per main run to avoid watching someone else's agents.

The watchdog runs until its pane is closed. It never takes focus and never stops the Herdr server.

## Functional smoke test

A minimal end-to-end test is:

1. start main inside Herdr and confirm `intercom({ action: "list" })` shows it;
2. start a uniquely named child with `PI_ORCHESTRATOR_PARENT` pointing to main;
3. ask the child for a short final response;
4. confirm main receives `<child> is idle.` followed by that response;
5. start the watcher with a short test interval/threshold;
6. leave the child idle long enough to see one stall alert; and
7. close it with `herdr-watchdog close <child-name>` and confirm no disappearance alert follows.

Use throwaway names and close the test watcher pane last.

## Troubleshooting

### `HERDR_ENV` is missing

Pi was not started inside a Herdr pane. Start Herdr from the outer terminal, then run Pi in its pane.

### Main never receives the child's final response

Check all of the following:

```bash
pi list | grep pi-intercom
```

- main and child were restarted or reloaded after installation;
- `intercom({ action: "list" })` shows both sessions;
- the child received `PI_ORCHESTRATOR_PARENT` before `pi` started;
- the parent target is unambiguous;
- `~/.pi/agent/intercom/config.json` does not set `enabled: false`; and
- the required idle-handoff extension is enabled in the child.

### `herdr-watchdog: command not found`

Use the copy under the skill's `scripts/` directory, run the local installer, or add `~/.local/bin` to `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### The watchdog alerts while a child is still legitimately working

Confirm Herdr can detect the agent, then increase `--threshold`. A long-running process with static output can look frozen if Herdr reports no lifecycle activity.

Useful Herdr diagnostics:

```bash
herdr agent list
herdr agent explain <child-name> --json
herdr integration status
```

### Intentional child closure creates a disappearance alert

Use `herdr-watchdog close <child-name>` instead of closing the pane directly.

### The wrong session receives watchdog alerts

The usual cause is single-quoting the `herdr pane run` command. Ensure the main pane's `$HERDR_PANE_ID` expands before the command is sent to the watchdog pane.

### Duplicate skill or extension warnings

Do not combine `pi install` of the repository with `scripts/install.sh`. Remove one installation source and restart Pi.

### Auto-resume continues work you wanted to inspect first

Remove the optional extension and restart/reload Pi:

```bash
rm -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/auto-resume-after-compaction.ts"
```

## Updating

For direct Pi package installation:

```bash
pi update --extensions
```

For a cloned/manual installation:

```bash
git pull --ff-only
./scripts/check-bundle.sh
./scripts/install.sh --force                 # core only
# or
./scripts/install.sh --with-auto-resume --force
```

## Uninstall

For a package installed from Git:

```bash
pi remove git:https://github.com/caina-barbosa/Herdr-orchestrator-bundle.git
```

If you installed by copying, remove only the bundle-owned files:

```bash
agent_dir=${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}
rm -rf "$agent_dir/skills/herdr-orchestrator"
rm -f "$agent_dir/extensions/orchestrator-idle-handoff.ts"
rm -f "$agent_dir/extensions/auto-resume-after-compaction.ts"  # only if installed
rm -f "$HOME/.local/bin/herdr-watchdog"
```

Remove `pi-intercom` only if no other workflow uses it:

```bash
pi remove npm:pi-intercom@0.9.2
```

Restart Pi after uninstalling resources.

## Security and privacy

- Pi extensions execute with the user's full operating-system permissions. Review TypeScript before installing it.
- The watchdog reads a few lines from local Pi session logs when preparing a stall alert. Those lines are sent only to the selected local main session through Herdr, but they can contain sensitive task context.
- `pi-intercom` uses local IPC and is a separate MIT-licensed dependency.
- Herdr and Pi are not vendored in this repository; follow their own licenses and security guidance.
- This repository is marked `UNLICENSED` and is intended for controlled private sharing unless the owner grants other terms.

## References

- [Herdr documentation](https://herdr.dev/docs/)
- [Herdr CLI repository](https://github.com/herdrdev/herdr)
- [Pi extensions documentation](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/extensions.md)
- [Pi skills documentation](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/skills.md)
- [Pi packages documentation](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/packages.md)
- [`pi-intercom`](https://github.com/nicobailon/pi-intercom)
