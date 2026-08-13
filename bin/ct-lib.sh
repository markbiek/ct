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

CT_STATE_DIR="${CT_STATE_DIR:-$HOME/.local/state/ct}"

ct_discover_repos() {
  local root
  for root in "$@"; do
    root="${root%/}"
    [[ -d "$root" ]] || continue

    if [[ -d "$root/.git" ]]; then
      printf '%s\n' "$root"
      continue
    fi

    # A worktree's .git is a file, so -type d skips worktrees for free.
    find "$root" -mindepth 2 -maxdepth 3 -type d -name .git 2>/dev/null \
      | while IFS= read -r gitdir; do
          dirname "$gitdir"
        done
  done
}

ct_recent_file() {
  printf '%s/recent\n' "${CT_STATE_DIR:-$HOME/.local/state/ct}"
}

ct_recent_add() {
  local repo="${1%/}"
  local file tmp
  file="$(ct_recent_file)"
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  printf '%s\n' "$repo" > "$tmp"
  if [[ -f "$file" ]]; then
    grep -Fxv -- "$repo" "$file" >> "$tmp" || true
  fi
  mv "$tmp" "$file"
}

ct_order_by_recent() {
  local file entry candidate
  local -a all
  file="$(ct_recent_file)"
  mapfile -t all

  if [[ -f "$file" ]]; then
    while IFS= read -r entry; do
      for candidate in "${all[@]}"; do
        if [[ "$candidate" == "$entry" ]]; then
          printf '%s\n' "$entry"
          break
        fi
      done
    done < "$file"
  fi

  for candidate in "${all[@]}"; do
    if [[ -f "$file" ]] && grep -Fxq -- "$candidate" "$file"; then
      continue
    fi
    printf '%s\n' "$candidate"
  done
}
