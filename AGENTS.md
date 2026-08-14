# AGENTS.md

`ct` pairs a git worktree, a tmux session, and a terminal workspace under one slug, so
several coding-agent sessions can run side by side. There is no database: task state is
derived on every invocation from `git worktree list`, `tmux ls`, and `cmux tree`.

## The one rule that is not negotiable

**This repository is publishable from commit one.** No employer names, internal
hostnames, ticket prefixes, or personal directory layout in code, comments, fixtures,
or docs. Fixtures use `myrepo`, `other`, `example`, `~/dev`, and the fictional ticket
prefix `ABC-857`.

Before any commit that adds fixtures or docs, scan all history:

    git grep -nIE '<employer terms>' $(git rev-list --all) -- . || echo CLEAN

Keep the actual term list out of this file — it is the thing being scanned for. The
maintainer knows it.

## Layout

| Path | Role |
| --- | --- |
| `bin/ct` | The CLI. Subcommands `new`, `switch`, `finish`, `list`. |
| `bin/ct-lib.sh` | Pure functions. Sourced, never executed. No tmux, cmux, fzf, or network. |
| `bin/ct-alfred` | Alfred adapter. Emits Script Filter JSON, shells out to `ct`. |
| `bin/ct-linear` | Prints assigned issues as `<identifier>\t<title>`. Optional. |
| `bin/tms` | tmux session starter, absorbed from a retired repo. |
| `alfred/build-plist.py` | **Generates** `alfred/info.plist`. |
| `tmux-start/profiles/` | Shipped pane layouts. |
| `tests/` | bats. `bats tests` runs all of them. |

User config lives outside the repo: `~/.config/ct/config.sh` (the `CT_ROOTS` array) and
`~/.config/tmux-start/` (directory-to-profile mappings and project scripts).

## Environment

- **bash 4+.** macOS ships 3.2 as `/bin/bash`. `bin/ct` refuses to run under it, and
  `ct-lib.sh` uses `mapfile` and `local -A`, so it cannot even be sourced there.
- Requires `git`, `tmux`, `jq`, `fzf`; `cmux` for the workspace half; `bats` for tests.

## Landmines that have already drawn blood

Each of these shipped once and was found by a whole-branch review after every per-task
review passed. Do not reintroduce them.

**1. Bare `tmux -t` targets match by prefix.** tmux resolves a target as exact, then
fnmatch, then **prefix**. `tmux kill-session -t auth` will destroy a live
`auth-refactor` session. Every target in this repo is anchored with `=`, as in
`tmux has-session -t "=$slug"`. Keep it that way. Note a leading `=` needs single
quotes in a shell you paste into — zsh treats bare `=foo` as an equals-expansion.

**2. A failing command substitution in an assignment aborts under `set -e`.** This has
been fixed eight separate times here. bash exempts every command in an `&&`/`||` list
except the one after the final operator, so `x="$(cmd)" || x=""` is safe but
`local x="$(cmd)"` is not — the `local` builtin masks the exit status. Declare first,
assign second.

**3. PATH order decides which bash `#!/usr/bin/env bash` finds.** `bin/ct-alfred` runs
under Alfred with a bare PATH and `/bin/bash` 3.2. It appends its directories to PATH so
the bats stub binaries stay in front — but it *prepends* the directory of the bash it
located, **inside the re-exec block only**. That block never runs during tests, because
bats already has a modern bash. Moving that prepend outside the block would let the real
`ct` shadow the test stubs and the whole suite would go green while testing the wrong
binary.

## Tests

`bats tests`. Three isolation rules exist because breaking them damages the developer's
real environment, not just the run:

- Any test that calls `tmux kill-server` must keep the guard
  `[[ -n "${CT_TMP:-}" && "${TMUX_TMPDIR:-}" == "$CT_TMP/tmux" ]]`. Unguarded, a
  `setup()` that died before isolating `TMUX_TMPDIR` kills the user's live tmux server.
- Any test that runs `install.sh` must set `CT_ALFRED_WORKFLOW_DIR` to a scratch path.
  Unset, `install.sh` resolves the user's real Alfred workflow directory and writes
  into it.
- `tests/e2e.bats` sets `GIT_CONFIG_GLOBAL=/dev/null`, so fixture commits do not pick up
  a real `core.hooksPath`.

Known coverage gap, worth closing rather than working around: **no test executes the
real `bin/ct`.** Every `ct` in `tests/alfred.bats` is a stub already running under a
modern bash. That is precisely where landmine 3 hid.

## Alfred

`alfred/info.plist` is **generated**. Edit `alfred/build-plist.py` and regenerate; never
hand-edit the XML, or the next regeneration silently reverts the change.

Alfred's plist schema is undocumented. The key values here were derived by reading
working workflows on a real machine, not from documentation — if a future Alfred version
misbehaves, re-derive them the same way rather than guessing.

`install.sh` resolves Alfred's workflow directory from
`defaults read com.runningwithcrayons.Alfred-Preferences syncfolder`, falling back to the
default location. **Never assume the default** — when a sync folder is configured, the
default directory is empty, and installing there succeeds while doing nothing. The
workflow is copied, not symlinked; Alfred does not reliably keep symlinked workflow
directories.

## Conventions

- Comments explain *why*, not *what*. Match the existing density — these files carry
  short rationales above anything non-obvious.
- Conventional-commit prefixes. No emoji anywhere.
- Prefer editing an existing file over adding one.
- Ask before large refactors or before touching files outside the obvious scope.
