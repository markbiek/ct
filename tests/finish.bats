#!/usr/bin/env bats

load helpers/fixtures

setup() {
  ct_load_lib
  CT_TMP="$(mktemp -d)"
  # -b trunk is required: a bare repo's HEAD never migrates to the first
  # pushed branch, so without it HEAD stays at init.defaultBranch (main here),
  # the clone warns "remote HEAD refers to nonexistent ref" and sets no
  # refs/remotes/origin/HEAD, and ct_trunk_ref has nothing to derive from.
  git init -q -b trunk --bare "$CT_TMP/remote.git"
  git init -q -b trunk "$CT_TMP/seed"
  git -C "$CT_TMP/seed" config user.email t@example.com
  git -C "$CT_TMP/seed" config user.name Test
  echo hello > "$CT_TMP/seed/file.txt"
  git -C "$CT_TMP/seed" add -A
  git -C "$CT_TMP/seed" commit -q -m init
  git -C "$CT_TMP/seed" remote add origin "$CT_TMP/remote.git"
  git -C "$CT_TMP/seed" push -q origin trunk
  git clone -q "$CT_TMP/remote.git" "$CT_TMP/myrepo"
  git -C "$CT_TMP/myrepo" config user.email t@example.com
  git -C "$CT_TMP/myrepo" config user.name Test
  ct_add_worktree "$CT_TMP/myrepo" "task-a" > /dev/null
  CT_WT="$CT_TMP/myrepo-wt/task-a"
}

teardown() {
  rm -rf "$CT_TMP"
}

@test "clean returns 0 for an untouched worktree" {
  run ct_worktree_clean "$CT_WT"
  [ "$status" -eq 0 ]
}

@test "clean reports uncommitted changes" {
  echo change >> "$CT_WT/file.txt"
  run ct_worktree_clean "$CT_WT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted"* ]]
}

@test "clean reports unpushed commits" {
  echo change >> "$CT_WT/file.txt"
  git -C "$CT_WT" add -A
  git -C "$CT_WT" commit -q -m work
  run ct_worktree_clean "$CT_WT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not on origin"* ]]
}

@test "clean reports untracked files" {
  touch "$CT_WT/scratch.txt"
  run ct_worktree_clean "$CT_WT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted"* ]]
}
