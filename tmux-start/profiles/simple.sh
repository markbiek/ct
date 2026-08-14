# simple profile: single window, single pane

setup_layout() {
  local session="$1"
  local directory="$2"

  tmux new-session -d -s "$session" -n "main" -c "$directory"
}

# Every profile must export both, because project scripts target panes through
# them (see projects/example.sh). There is only one pane here, so both are 0;
# omitting them makes any "simple:<project>" mapping die with
# "SHELL_PANE: unbound variable".
CLAUDE_PANE=0
SHELL_PANE=0
