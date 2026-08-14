#!/usr/bin/env bats

load helpers/fixtures

setup() { ct_load_lib; }

@test "parse_worktrees emits path and branch" {
  run bash -c "source '$CT_REPO/bin/ct-lib.sh'; ct_parse_worktrees <<'EOF'
worktree /home/u/dev/myrepo
HEAD 5db1ba08573
branch refs/heads/main

worktree /home/u/dev/myrepo-wt/task-a
HEAD 53ab671bf32
branch refs/heads/task-a

EOF"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "$(printf '/home/u/dev/myrepo\tmain')" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "parse_worktrees marks detached heads" {
  run bash -c "source '$CT_REPO/bin/ct-lib.sh'; ct_parse_worktrees <<'EOF'
worktree /tmp/thing
HEAD abc123
detached

EOF"
  [ "$output" = "$(printf '/tmp/thing\t(detached)')" ]
}

@test "parse_tmux splits session name from path" {
  run bash -c "source '$CT_REPO/bin/ct-lib.sh'; ct_parse_tmux <<'EOF'
notes:/home/u/notes
task-a:/home/u/dev/myrepo-wt/task-a
EOF"
  [ "$(printf '%s\n' "$output" | head -1)" = "$(printf 'notes\t/home/u/notes')" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "parse_tmux keeps a final line with no trailing newline" {
  run bash -c "printf 'a:/p1\nb:/p2' | { source '$CT_REPO/bin/ct-lib.sh'; ct_parse_tmux; }"
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "$(printf 'b\t/p2')" ]
}

@test "parse_worktrees keeps a final record with no trailing newline" {
  run bash -c "printf 'worktree /x\nHEAD abc\nbranch refs/heads/main' | { source '$CT_REPO/bin/ct-lib.sh'; ct_parse_worktrees; }"
  [ "$output" = "$(printf '/x\tmain')" ]
}

@test "parse_cmux emits workspace ref and title" {
  run bash -c "source '$CT_REPO/bin/ct-lib.sh'; ct_parse_cmux <<'EOF'
{\"windows\":[{\"ref\":\"window:8\",\"workspaces\":[{\"ref\":\"workspace:14\",\"title\":\"task-a\"},{\"ref\":\"workspace:15\",\"title\":\"task-b\"}]}]}
EOF"
  [ "$(printf '%s\n' "$output" | head -1)" = "$(printf 'workspace:14\ttask-a')" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}
