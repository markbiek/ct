#!/usr/bin/env bats

load helpers/fixtures

setup() {
  CT_TESTDIR="$(mktemp -d)"
  export CT_BIN_DIR="$CT_TESTDIR/bin"
  export CT_CONFIG_DIR="$CT_TESTDIR/config"
  # Default to a scratch path that doesn't exist, so any test that doesn't
  # care about Alfred exercises the "absent" path instead of falling through
  # to the real `defaults read` lookup and writing into the user's actual
  # Alfred workflow directory. Tests that care override this.
  export CT_ALFRED_WORKFLOW_DIR="$CT_TESTDIR/unused-alfred-workflows"
}

teardown() {
  rm -rf "$CT_TESTDIR"
}

@test "install.sh symlinks tms into the bin dir" {
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CT_BIN_DIR/tms" ]
  [ "$(readlink -f "$CT_BIN_DIR/tms")" = "$CT_REPO/bin/tms" ]
}

@test "install.sh symlinks the profiles directory" {
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CT_CONFIG_DIR/tmux-start/profiles" ]
  [ -f "$CT_CONFIG_DIR/tmux-start/profiles/simple.sh" ]
}

@test "install.sh seeds config.sh from the example" {
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$CT_CONFIG_DIR/tmux-start/config.sh" ]
  [ ! -L "$CT_CONFIG_DIR/tmux-start/config.sh" ]
}

@test "install.sh never overwrites an existing config.sh" {
  mkdir -p "$CT_CONFIG_DIR/tmux-start"
  echo "MINE=1" > "$CT_CONFIG_DIR/tmux-start/config.sh"
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$CT_CONFIG_DIR/tmux-start/config.sh")" = "MINE=1" ]
}

@test "install.sh never overwrites an existing project script" {
  mkdir -p "$CT_CONFIG_DIR/tmux-start/projects"
  echo "MINE=1" > "$CT_CONFIG_DIR/tmux-start/projects/mine.sh"
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$CT_CONFIG_DIR/tmux-start/projects/mine.sh")" = "MINE=1" ]
}

@test "install.sh is idempotent" {
  "$CT_REPO/install.sh"
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$CT_CONFIG_DIR/tmux-start/profiles/profiles" ]
}

@test "install.sh refuses to clobber a real profiles directory" {
  mkdir -p "$CT_CONFIG_DIR/tmux-start/profiles"
  run "$CT_REPO/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"real directory"* ]]
}

@test "install.sh refuses when tmux-start is itself a symlink" {
  mkdir -p "$CT_CONFIG_DIR" "$CT_TESTDIR/legacy"
  ln -s "$CT_TESTDIR/legacy" "$CT_CONFIG_DIR/tmux-start"
  run "$CT_REPO/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink"* ]]
}

@test "install.sh symlinks ct-alfred into the bin dir" {
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -L "$CT_BIN_DIR/ct-alfred" ]
  [ "$(readlink -f "$CT_BIN_DIR/ct-alfred")" = "$CT_REPO/bin/ct-alfred" ]
}

@test "install.sh copies the workflow into the Alfred directory" {
  export CT_ALFRED_WORKFLOW_DIR="$CT_TESTDIR/workflows"
  mkdir -p "$CT_ALFRED_WORKFLOW_DIR"
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$CT_TESTDIR/workflows/ct-alfred/info.plist" ]
}

@test "install.sh still succeeds when Alfred is absent" {
  export CT_ALFRED_WORKFLOW_DIR="$CT_TESTDIR/nope/workflows"
  run "$CT_REPO/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping the workflow"* ]]
}
