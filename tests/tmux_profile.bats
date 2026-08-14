#!/usr/bin/env bats

load helpers/fixtures

setup() {
  CT_TMP="$(mktemp -d)"
  ct_isolate_tmux "$CT_TMP"
  CT_SESSION="ct-profiletest"
  CT_DIR="$CT_TMP/work"
  mkdir -p "$CT_DIR"
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

@test "dev profile creates one window named main" {
  source "$CT_REPO/tmux-start/profiles/dev.sh"
  setup_layout "$CT_SESSION" "$CT_DIR"
  run tmux list-windows -t "=$CT_SESSION" -F '#{window_name}'
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "dev profile creates exactly two panes" {
  source "$CT_REPO/tmux-start/profiles/dev.sh"
  setup_layout "$CT_SESSION" "$CT_DIR"
  run tmux list-panes -t "=$CT_SESSION:main" -F '#{pane_index}'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "dev profile panes are side by side" {
  source "$CT_REPO/tmux-start/profiles/dev.sh"
  setup_layout "$CT_SESSION" "$CT_DIR"
  # A vertical split means both panes share the same top edge.
  run tmux list-panes -t "=$CT_SESSION:main" -F '#{pane_top}'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '0\n0')" ]
}

@test "dev profile exports CLAUDE_PANE and SHELL_PANE" {
  source "$CT_REPO/tmux-start/profiles/dev.sh"
  [ "$CLAUDE_PANE" = "0" ]
  [ "$SHELL_PANE" = "1" ]
}
