# dev profile: one window, two 50/50 vertical panes
# Pane 0 (left): the coding agent
# Pane 1 (right): shell, or the project command for a main checkout

setup_layout() {
  local session="$1"
  local directory="$2"

  tmux new-session -d -s "$session" -n "main" -c "$directory"
  # `=` forces an exact session-name match. tmux falls back to a prefix match on
  # a bare target, so keep every target in this file anchored.
  tmux split-window -h -p 50 -t "=$session:main" -c "$directory"

  tmux select-window -t "=$session:main"
  tmux select-pane -t "=$session:main.0"
}

CLAUDE_PANE=0
SHELL_PANE=1
