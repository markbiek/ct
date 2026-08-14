#!/usr/bin/env bats

load helpers/fixtures

setup() {
  ct_load_lib
  CT_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$CT_TMP"
}

# Real files, not process substitution. ct_tasks passes mktemp files, and
# ct_join_task_state re-reads the tmux and cmux files once per worktree row.
# A <(...) FIFO is single-use, so with process substitution every row after
# the first would see empty input and the tests would pass for the wrong
# reason — and would not catch a regression affecting multi-row input.
ct_fixture() {
  # The content argument arrives via "$(printf ...)" at each call site, which
  # strips its trailing newline. Restore it here so the file matches what
  # ct_tasks actually writes (every row newline-terminated) -- without it the
  # final line of a multi-line fixture has no trailing newline, `while read`
  # drops it, and multi-row tests fail for a reason unrelated to what they're
  # testing.
  printf '%s\n' "$2" > "$CT_TMP/$1"
  printf '%s' "$CT_TMP/$1"
}

@test "join_task_state marks a worktree with no session or workspace" {
  run ct_join_task_state \
    "$(ct_fixture wt "$(printf '/r/myrepo-wt/task-a\tbranch-a\n')")" \
    "$(ct_fixture tmux '')" \
    "$(ct_fixture cmux '')"
  [ "$output" = "$(printf 'task-a\t/r/myrepo\tbranch-a\tworktree')" ]
}

@test "join_task_state marks tmux and cmux when both are live" {
  run ct_join_task_state \
    "$(ct_fixture wt "$(printf '/r/myrepo-wt/task-a\tbranch-a\n')")" \
    "$(ct_fixture tmux "$(printf 'task-a\t/r/myrepo-wt/task-a\n')")" \
    "$(ct_fixture cmux "$(printf 'workspace:3\ttask-a\n')")"
  [ "$output" = "$(printf 'task-a\t/r/myrepo\tbranch-a\tworktree/tmux/cmux')" ]
}

@test "join_task_state ignores worktrees outside a -wt directory" {
  run ct_join_task_state \
    "$(ct_fixture wt "$(printf '/r/myrepo\tmain\n')")" \
    "$(ct_fixture tmux '')" \
    "$(ct_fixture cmux '')"
  [ "$output" = "" ]
}

@test "join_task_state re-reads the state files for every worktree row" {
  run ct_join_task_state \
    "$(ct_fixture wt "$(printf '/r/a-wt/task-a\tbr-a\n/r/b-wt/task-b\tbr-b\n')")" \
    "$(ct_fixture tmux "$(printf 'task-a\t/r/a-wt/task-a\ntask-b\t/r/b-wt/task-b\n')")" \
    "$(ct_fixture cmux '')"
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "$(printf 'task-b\t/r/b\tbr-b\tworktree/tmux')" ]
}
