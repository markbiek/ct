#!/usr/bin/env bats

load helpers/fixtures

setup() {
  ct_load_lib
  CT_TMP="$(mktemp -d)"
  export CT_STATE_DIR="$CT_TMP/state"
  mkdir -p "$CT_TMP/roots/alpha/.git"
  mkdir -p "$CT_TMP/roots/beta/.git"
  mkdir -p "$CT_TMP/roots/nested/gamma/.git"
  # A worktree: .git is a file, so it must not be discovered.
  mkdir -p "$CT_TMP/roots/alpha-wt/some-task"
  echo "gitdir: /elsewhere" > "$CT_TMP/roots/alpha-wt/some-task/.git"
}

teardown() {
  # A test deliberately chmods a directory to 000; restore before removal.
  chmod -R u+rwx "$CT_TMP" 2>/dev/null || true
  rm -rf "$CT_TMP"
}

@test "discover finds repos one level down" {
  run ct_discover_repos "$CT_TMP/roots"
  [[ "$output" == *"$CT_TMP/roots/alpha"* ]]
  [[ "$output" == *"$CT_TMP/roots/beta"* ]]
}

@test "discover finds repos two levels down" {
  run ct_discover_repos "$CT_TMP/roots"
  [[ "$output" == *"$CT_TMP/roots/nested/gamma"* ]]
}

@test "discover excludes worktrees" {
  run ct_discover_repos "$CT_TMP/roots"
  [[ "$output" != *"some-task"* ]]
}

@test "discover includes a root that is itself a repo" {
  run ct_discover_repos "$CT_TMP/roots/alpha"
  [ "$output" = "$CT_TMP/roots/alpha" ]
}

@test "discover skips roots that do not exist" {
  run ct_discover_repos "$CT_TMP/nope"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "recent_add prepends and deduplicates" {
  ct_recent_add "/a"
  ct_recent_add "/b"
  ct_recent_add "/a"
  run cat "$(ct_recent_file)"
  [ "$output" = "$(printf '/a\n/b')" ]
}

@test "order_by_recent puts recent repos first, keeps the rest in order" {
  ct_recent_add "/b"
  run bash -c "printf '/a\n/b\n/c\n' | { source '$CT_REPO/bin/ct-lib.sh'; ct_order_by_recent; }"
  [ "$output" = "$(printf '/b\n/a\n/c')" ]
}

@test "discover survives an unreadable subdirectory under a root" {
  mkdir -p "$CT_TMP/roots/locked/sub"
  chmod 000 "$CT_TMP/roots/locked"
  run bash -c "set -euo pipefail; source '$CT_REPO/bin/ct-lib.sh'; ct_discover_repos '$CT_TMP/roots'"
  chmod 755 "$CT_TMP/roots/locked"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CT_TMP/roots/alpha"* ]]
}

@test "order_by_recent deduplicates repeated input" {
  ct_recent_add "/b"
  run bash -c "printf '/a\n/a\n/b\n/b\n' | { source '$CT_REPO/bin/ct-lib.sh'; ct_order_by_recent; }"
  [ "$output" = "$(printf '/b\n/a')" ]
}
