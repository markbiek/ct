#!/usr/bin/env bats
#
# End-to-end smoke test for bin/ct: new -> list -> switch -> finish against a
# real scratch repo. Everything ct touches outside the repo is redirected:
# tmux to a private server, cmux and claude to stubs, and $HOME to a throwaway
# tree. Nothing here can reach a live session, workspace, or config file.

load helpers/fixtures

setup() {
  CT_TMP="$(mktemp -d)"
  ct_isolate_tmux "$CT_TMP"

  # Keep every git call in this file away from the real global config: a
  # core.hooksPath there would run the user's hooks against fixture commits.
  export GIT_CONFIG_GLOBAL=/dev/null

  # Stubs ahead of everything on PATH. cmux logs what it was asked to do and
  # succeeds, so ct_ensure_workspace takes its real path without creating a
  # workspace; claude keeps `ct_ensure_tmux`'s send-keys from starting a real
  # agent inside the isolated server.
  CT_STUBS="$CT_TMP/stubs"
  mkdir -p "$CT_STUBS"
  cat > "$CT_STUBS/cmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CT_TMP/cmux.log"
if [[ "\$1" == "current-window" ]]; then
  echo win-stub
fi
exit 0
EOF
  cat > "$CT_STUBS/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CT_TMP/claude.log"
exit 0
EOF
  chmod +x "$CT_STUBS/cmux" "$CT_STUBS/claude"
  PATH="$CT_STUBS:$CT_REPO/bin:$PATH"
  export PATH

  # A throwaway tmux-start config, so tms never reads the real one. One
  # non-matching mapping rather than an empty array: `${!DIR_MAPPINGS[@]}` on an
  # empty associative array is an unbound-variable error under `set -u` in older
  # bash 4.
  CT_TMSCONF="$CT_TMP/tmsconf"
  mkdir -p "$CT_TMSCONF/profiles"
  cp "$CT_REPO/tmux-start/profiles/dev.sh" "$CT_TMSCONF/profiles/dev.sh"
  cat > "$CT_TMSCONF/config.sh" <<'EOF'
declare -A DIR_MAPPINGS=( ["/nonexistent-ct-e2e"]="dev" )
DEFAULT_PROFILE="dev"
EOF
  export TMS_CONFIG_DIR="$CT_TMSCONF"

  # -b trunk is required on the bare repo: a bare repo's HEAD never migrates to
  # the first pushed branch, so without it the clone sets no
  # refs/remotes/origin/HEAD and ct_trunk_ref has nothing to derive from.
  git init -q -b trunk --bare "$CT_TMP/remote.git"
  git init -q -b trunk "$CT_TMP/seed"
  git -C "$CT_TMP/seed" config user.email t@example.com
  git -C "$CT_TMP/seed" config user.name Test
  echo hello > "$CT_TMP/seed/file.txt"
  git -C "$CT_TMP/seed" add -A
  git -C "$CT_TMP/seed" commit -q -m init
  git -C "$CT_TMP/seed" remote add origin "$CT_TMP/remote.git"
  git -C "$CT_TMP/seed" push -q origin trunk

  mkdir -p "$CT_TMP/roots"
  git clone -q "$CT_TMP/remote.git" "$CT_TMP/roots/myrepo"
  git -C "$CT_TMP/roots/myrepo" config user.email t@example.com
  git -C "$CT_TMP/roots/myrepo" config user.name Test
  CT_R="$CT_TMP/roots/myrepo"
  CT_WTROOT="$CT_TMP/roots/myrepo-wt"

  # CT_ROOTS is a bash array declared inside bin/ct, so it cannot be set from
  # the environment (the README says so). The only way to aim ct at a scratch
  # tree is its config file, which it reads from $HOME -- hence the throwaway
  # HOME. The two paths that have their own overrides get them as well, so a
  # missed default cannot fall through to the real MRU file or Claude history.
  export HOME="$CT_TMP/home"
  mkdir -p "$HOME/.config/ct"
  cat > "$HOME/.config/ct/config.sh" <<EOF
CT_ROOTS=("$CT_TMP/roots")
EOF
  export CT_STATE_DIR="$CT_TMP/state"
  export CT_CLAUDE_HOME="$CT_TMP/claude-home"
}

teardown() {
  # Safe only because setup() pointed TMUX_TMPDIR at $CT_TMP: this kills the
  # per-test server, never the user's. Matching against $CT_TMP rather than
  # just testing for non-empty means an inherited TMUX_TMPDIR cannot stand in
  # for the isolation a setup() that died before ct_isolate_tmux never set up.
  if [[ -n "${CT_TMP:-}" && "${TMUX_TMPDIR:-}" == "$CT_TMP/tmux" ]]; then
    tmux kill-server 2>/dev/null || true
  fi
  rm -rf "$CT_TMP"
}

@test "new, list, switch, and finish drive one task through its whole life" {
  run ct new --repo "$CT_R" --name "First Task"
  [ "$status" -eq 0 ]
  [ -d "$CT_WTROOT/first-task" ]

  run git -C "$CT_WTROOT/first-task" rev-parse --abbrev-ref HEAD
  [ "$output" = "first-task" ]

  run tmux has-session -t "=first-task"
  [ "$status" -eq 0 ]

  run ct list
  [ "$status" -eq 0 ]
  [[ "$output" == *"first-task"* ]]
  [[ "$output" == *"worktree/tmux"* ]]

  run ct switch first-task
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reusing tmux session first-task"* ]]

  run ct finish first-task
  [ "$status" -eq 0 ]
  [ ! -d "$CT_WTROOT/first-task" ]

  run tmux has-session -t "=first-task"
  [ "$status" -ne 0 ]

  # The one promise a user cannot recover from if broken.
  run git -C "$CT_R" show-ref --verify --quiet refs/heads/first-task
  [ "$status" -eq 0 ]
}

@test "finish kills only the exact session, not one whose name starts with the slug" {
  ct new --repo "$CT_R" --name "auth" > /dev/null
  ct new --repo "$CT_R" --name "auth refactor" > /dev/null

  # The user closed auth's own session by hand; auth-refactor is still running
  # an agent. tmux resolves a bare -t target by prefix once exact and fnmatch
  # miss, so an unguarded `has-session -t auth` finds auth-refactor instead.
  tmux kill-session -t "=auth"

  run ct finish auth
  [ "$status" -eq 0 ]

  run tmux has-session -t "=auth-refactor"
  [ "$status" -eq 0 ]
}

@test "new does not mistake a prefix-named live session for the task's own" {
  ct new --repo "$CT_R" --name "auth refactor" > /dev/null

  run ct new --repo "$CT_R" --name "auth"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created tmux session auth"* ]]
}

@test "a new task branch has no upstream, so the first push cannot land on trunk" {
  ct new --repo "$CT_R" --name "push test" > /dev/null

  run git -C "$CT_WTROOT/push-test" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
  [ "$status" -ne 0 ]
}
