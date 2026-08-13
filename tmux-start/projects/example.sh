# Example project script.
# Named to match the ":project" half of a DIR_MAPPINGS entry, so
# ["$HOME/dev/myproject"]="dev:myproject" loads projects/myproject.sh.
#
# Runs after the profile builds the layout. Use $SHELL_PANE to target the
# right-hand pane; $CLAUDE_PANE is reserved for the agent.

run_project_commands() {
  local session="$1"
  tmux send-keys -t "$session:main.$SHELL_PANE" 'echo hello from the project script' C-m
}
