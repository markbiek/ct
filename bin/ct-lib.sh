# ct-lib.sh - pure functions for ct. Sourced, never executed.
# Everything here must be free of tmux, cmux, fzf, and network calls so the
# bats suite can exercise it directly.

ct_slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

ct_repo_name() {
  basename "${1%/}"
}

ct_worktree_root() {
  local repo="${1%/}"
  printf '%s/%s-wt' "$(dirname "$repo")" "$(basename "$repo")"
}

ct_worktree_path() {
  printf '%s/%s' "$(ct_worktree_root "$1")" "$2"
}
