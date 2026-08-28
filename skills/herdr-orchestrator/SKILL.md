---
name: herdr-orchestrator
description: |
  Orchestrate multi-slice work by launching named standalone Pi sessions in
  Herdr panes, coordinating via intercom and the idle-handoff extension, and
  keeping the Herdr session clean. Use when the user asks to orchestrate
  approved slices with Herdr. Requires HERDR_ENV=1.
---

# Herdr Orchestrator

You are main. Children are real Pi processes in Herdr panes — never `subagent` or workflow children. Verify `test "${HERDR_ENV:-}" = 1` first; if it fails, stop.

Focus belongs to the user — never take it. Every creating/moving command carries `--no-focus`, and `tab focus`/`pane focus`/`workspace focus` are not yours to run; to get the user's attention, use `herdr notification show`.

Default models: Sol (`openai/gpt-5.6-sol`) for main, Terra (`openai/gpt-5.6-terra`) for complex work and review, Luna (`openai/gpt-5.6-luna`) for small work. Use the direct `openai/` provider, not `truefoundry/openai-group/...`. User's role map wins.

## Process

1. Admit each slice: authorized outcome, non-goals, dependencies, ownership area, proof commands. Block and ask one ruling for missing authority or unknown acceptance.
2. Build a true-dependency graph. Launch ready slices up to the session cap (default 7). One writer per area; one writer for integration.
3. Implementers commit one checkpoint and report commit, paths, checks, risks via idle handoff. Require a failing test for behavior work; cheapest valid check otherwise.
4. Integrate by cherry-picking checkpoints in dependency order in the clean integration checkout. One independent read-only review per slice (batch ≤3 low-risk) over the exact range: PASS accept / FAIL repair in the worktree / BLOCKED roll back / TRASH restart. Author and reviewer are a pair — keep both alive through the loop: findings go back to the author to repair, the same reviewer re-reviews, close the pair on PASS. Fresh agents only when the user asks or you judge a context poisoned (looping on a wrong belief, contaminated, near exhaustion) — say so in your report.
5. Finish: run repository validation once, report commits + risks, then clean up everything you created. Never push unless asked.

## Launch a child

Get your intercom name first: `intercom({action:"list"})` — copy the entry marked `self` as `$MAIN`. If it is absent, return BLOCKED.

Children never live in your tab (see Watchdog for your tab's layout). Same-cwd children go in group tabs — one tab per group (speccers, qc, …):

```bash
herdr tab create --workspace <your-ws> --label <group> --cwd "$PWD" --no-focus   # once per group
# first child uses .result.root_pane.pane_id; for more children:
herdr pane split --pane <that-pane> --direction right --cwd "$PWD" \
  --env PI_ORCHESTRATOR_PARENT="$MAIN" --no-focus
# tab root panes have no --env: inject with herdr pane run <pane> "export PI_ORCHESTRATOR_PARENT=$MAIN"
```

Isolated worktree child (creates workspace + tab + pane at the checkout; Herdr owns the worktree path):

```bash
herdr worktree create --cwd "$REPO" --branch "pi/$RUN/$SLICE" --base "$BASE" \
  --label "$SLICE" --no-focus
# workspace: .result.workspace.workspace_id, pane: .result.root_pane.pane_id
# checkout path: .result.worktree.path
```

`worktree create` has no `--env`, so inject the parent into the shell before starting the agent:

```bash
herdr pane run <pane-id> "export PI_ORCHESTRATOR_PARENT=$MAIN"
```

**Callsign:** choose one short prefix at run start (e.g. `sdk374-`) — it is yours for your whole life as orchestrator. Every child you ever spawn, across every phase (research, spec, impl, qc), is named `<callsign><role>` (`sdk374-spec01`, `sdk374-qcspec01`). Start Pi (herdr name and `--name` must match; name follows `[a-z][a-z0-9_-]{0,31}`, unique):

```bash
herdr agent start <name> --kind pi --pane <pane-id> --timeout 60000 \
  -- --name <name> --model <model>
```

Confirm the child appears in `intercom({action:"list"})` before sending work.

## Communicate

Send the goal (no `--wait`; do not read the pane afterwards):

```bash
herdr agent prompt <name> "<goal>"
```

The goal must state: worktree/cwd, main's name, outcome, non-goals, proof commands, "commit one checkpoint, end with commit ID + paths + results + risks, then freeze", and "do not use subagent or workflow; do not push".

Once the watchdog script is properly set up and you have confirmed that a spawned child is running, do not poll it or use a command to wait for it. Continue with any work you still need to do in this round, including dispatching other children and doing independent work. When you have finished that work and are waiting for the children, end your round. The watchdog will automatically deliver their final responses and any stall or disappearance alerts. Keeping the round open to poll or check the children's state delays those messages.

For mid-run questions or decisions, use `intercom({action:"send"|"ask", to:<name>, ...})`. If a handoff never arrives, inspect:

```bash
herdr agent get <name>
herdr agent read <name> --source recent-unwrapped --lines 120
```

`blocked` means the child shows an approval/question UI — read the pane, then answer via `herdr agent prompt` or `herdr agent send-keys <name> <key>`.

Notify the user at real decision points (verdict in, run blocked, validation done):

```bash
herdr notification show "<title>" --body "<text>" --sound done|request
```

## Watchdog

Your tab holds exactly two panes: you, and the watchdog — split down at minimal height. Start it once, before the first child; it watches your callsign for your whole life. It discovers children by prefix each poll, so phases come and go under the one watchdog — it never needs a roster or restart:

```bash
herdr pane split --current --direction down --ratio 0.95 --cwd "$PWD" --no-focus
herdr pane run <pane-id> "herdr-watchdog $HERDR_PANE_ID --prefix <callsign> [--interval 60] [--threshold 180]"
```

Double quotes are load-bearing: `$HERDR_PANE_ID` must expand in *your* shell to *your* pane so alerts reach you — single-quoted it resolves to the watchdog's own pane and every alert goes nowhere.

If `herdr-watchdog` is not on PATH, run it from this skill's `scripts/` dir.

It alerts — desktop notification plus a `WATCHDOG:` prompt into main's pane — once per stall episode when a child stays non-working past the threshold (re-arms if it resumes), and when a child disappears without an acknowledged close. Note: a child stuck on `ask_user_question` reports `idle`, not `blocked`; the watchdog catches both. On an alert, check the child (`agent get`/`read`), then answer, repair, or close it. The watchdog pane is the last pane you close.

## Integrate and verify

Main verifies checkpoints itself in the checkout (`git -C <wt> diff --name-only $BASE $COMMIT`), cherry-picks into the integration checkout, and gives the reviewer the exact range `$accepted..$candidate`. Reviewers run in the integration checkout, read-only. Roll back only when the checkout is clean and HEAD is the candidate.

## Cleanup — no stale anything

Close each child when its role is done for good (pair reached PASS / checkpoint accepted).

```bash
herdr-watchdog close <name>                # ack + close pane; keeps the watchdog silent
herdr worktree remove --workspace <ws-id>  # removes checkout (add --force if dirty)
git -C "$REPO" branch -D "pi/$RUN/$SLICE"  # after PASS only
```

Remove the worktree before closing its last pane — closing the last pane destroys the workspace, after which only `git worktree remove <path>` can reclaim the checkout. Use raw `herdr pane close <pane-id>` only for agentless panes (e.g. the watchdog).

Audit: take `herdr api snapshot > /tmp/<run>-pre.json` before launching anything and diff against a final snapshot — plus `git -C "$REPO" worktree list && git -C "$REPO" branch --list 'pi/*'` and `intercom({action:"list"})` — everything must match pre-run state. Never close panes, tabs, or workspaces you did not create. Never run `herdr server stop`.
