#!/usr/bin/env bats

load helpers/fixtures

setup() {
  CT_TMP="$(mktemp -d)"
  ct_isolate_tmux "$CT_TMP"
  CT_SESSION="ct-flagtest"
  CT_DIR="$CT_TMP/$CT_SESSION"
  mkdir -p "$CT_DIR"

  # A throwaway tmux-start config whose project script leaves a marker file.
  CT_CONF="$CT_TMP/tmsconf"
  mkdir -p "$CT_CONF/profiles" "$CT_CONF/projects"
  cp "$CT_REPO/tmux-start/profiles/simple.sh" "$CT_CONF/profiles/simple.sh"
  cat > "$CT_CONF/config.sh" <<EOF
declare -A DIR_MAPPINGS=( ["$CT_DIR"]="simple:marker" )
DEFAULT_PROFILE="simple"
EOF
  cat > "$CT_CONF/projects/marker.sh" <<EOF
run_project_commands() { touch "$CT_TMP/ran"; }
EOF
}

teardown() {
  # Only kill the isolated server; if setup() died before ct_isolate_tmux,
  # an unguarded kill-server would hit the user's default socket. Matching the
  # exact path keeps an inherited TMUX_TMPDIR from satisfying the guard.
  if [[ -n "${CT_TMP:-}" && "${TMUX_TMPDIR:-}" == "$CT_TMP/tmux" ]]; then
    tmux kill-server 2>/dev/null || true
  fi
  rm -rf "$CT_TMP"
}

@test "--no-attach creates the session and returns without attaching" {
  run env TMS_CONFIG_DIR="$CT_CONF" "$CT_REPO/bin/tms" --no-attach --no-project "$CT_DIR"
  [ "$status" -eq 0 ]
  run tmux has-session -t "=$CT_SESSION"
  [ "$status" -eq 0 ]
}

@test "--no-attach on an existing session still returns without attaching" {
  env TMS_CONFIG_DIR="$CT_CONF" "$CT_REPO/bin/tms" --no-attach --no-project "$CT_DIR"
  run env TMS_CONFIG_DIR="$CT_CONF" "$CT_REPO/bin/tms" --no-attach --no-project "$CT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"existing session"* ]]
}

@test "--no-project skips run_project_commands, and omitting it runs them" {
  env TMS_CONFIG_DIR="$CT_CONF" "$CT_REPO/bin/tms" --no-attach --no-project "$CT_DIR"
  [ ! -f "$CT_TMP/ran" ]

  tmux kill-session -t "=$CT_SESSION"
  env TMS_CONFIG_DIR="$CT_CONF" "$CT_REPO/bin/tms" --no-attach "$CT_DIR"
  [ -f "$CT_TMP/ran" ]
}

@test "an unknown flag is an error" {
  run env TMS_CONFIG_DIR="$CT_CONF" "$CT_REPO/bin/tms" --nope "$CT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}
