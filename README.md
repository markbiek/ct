# ct

Pairs a git worktree, a tmux session, and a terminal workspace under one slug,
so you can run several coding-agent sessions side by side without losing track
of which is which.

Built for [cmux](https://cmux.com), tmux, and Claude Code.

## Requirements

- bash 4+ (macOS ships 3.2: `brew install bash`)
- git, tmux, jq, fzf
- cmux, for the workspace half
- bats, to run the tests

## Install

    git clone https://github.com/<you>/ct ~/dev/ct
    ~/dev/ct/install.sh

Symlinks `ct`, `ct-linear`, and `tms` into `~/.local/bin`, symlinks the shipped
tmux profiles into `~/.config/tmux-start/profiles`, and seeds
`~/.config/tmux-start/config.sh` from the example if you do not already have
one. Your config is never overwritten.

## Usage

    ct new    [--repo <path>] [--name <text>] [--no-focus]
    ct switch [<slug>]
    ct finish [<slug>] [--force]
    ct list   [--json]

`ct new` with no flags prompts for a repo (fzf, most-recently-used first) and a
name (your assigned Linear issues, if configured, or free text).

## Conventions

A task name slugifies to `[a-z0-9-]`. That slug names everything:

| Artifact | Location |
| --- | --- |
| Worktree | `<repo-parent>/<repo>-wt/<slug>` |
| Branch | `<slug>` |
| tmux session | `<slug>` |
| cmux workspace | `<slug>` |

New branches are cut from `origin/HEAD`. An existing branch of the same name is
reused, fetched from origin first if it is remote-only. `ct finish` never
deletes a branch.

## State

There is no database. Tasks are derived on every invocation from
`git worktree list`, `tmux ls`, and `cmux tree --all --json`. The only
persisted file is `~/.local/state/ct/recent`, which orders the repo picker;
deleting it degrades nothing.

## Configuration

Search roots, in `~/.config/ct/config.sh`:

    CT_ROOTS=("$HOME/dev" "$HOME/work")

`CT_ROOTS` is a bash array, so it cannot be overridden from the environment —
`CT_ROOTS=... ct list` will not work. Edit the config file.

Discovery finds a repository whose `.git` sits one or two levels below a root —
so with `$HOME/dev` as a root, both `~/dev/myrepo` and `~/dev/org/myrepo` are
found, but `~/dev/a/b/myrepo` is not. Add a deeper root if you need it.
Worktrees are skipped automatically, because a worktree's `.git` is a file
rather than a directory.

Per-directory tmux layouts, in `~/.config/tmux-start/config.sh` — map a
directory prefix to a profile and an optional project script:

    declare -A DIR_MAPPINGS=(
      ["$HOME/dev/myproject"]="dev:myproject"
    )

Project scripts live in `~/.config/tmux-start/projects/`; see `example.sh` for
the contract. They run for main checkouts only, never for task worktrees.

## Linear (optional)

`ct-linear` resolves an API key from `$LINEAR_API_KEY`, then `$CT_LINEAR_KEY_CMD`
(any command printing the key — `pass`, `op read`, and so on), then macOS
Keychain:

    security add-generic-password -s linear-api -a "$USER" -w

With no key configured, the name prompt is plain free text.

## Tests

    bats tests/

Unit tests cover the pure functions in `bin/ct-lib.sh`. The tmux tests run
against an isolated tmux server via `TMUX_TMPDIR` and never touch your live
sessions. The cmux integration is smoke-tested by hand.

## License

MIT
