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
    # `|| true` because find exits 1 on any unreadable subdirectory, and with
    # pipefail that would abort the caller even though the readable repos were
    # found and printed.
    find "$root" -mindepth 2 -maxdepth 3 -type d -name .git 2>/dev/null \
      | while IFS= read -r gitdir; do
          dirname "$gitdir"
        done || true
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
  # Temp file must be a sibling of the destination: mv is only atomic within
  # one filesystem, and $TMPDIR is often a different volume.
  tmp="$(mktemp "${file}.XXXXXX")"
  printf '%s\n' "$repo" > "$tmp"
  if [[ -f "$file" ]]; then
    grep -Fxv -- "$repo" "$file" >> "$tmp" || true
  fi
  mv "$tmp" "$file"
}

ct_order_by_recent() {
  local file entry candidate
  local -a all
  local -A emitted=()
  file="$(ct_recent_file)"
  mapfile -t all

  # `emitted` is what deduplicates. Suppressing repeats by MRU-file membership
  # alone would let a duplicate stdin entry through whenever that entry is not
  # in the MRU file, and overlapping CT_ROOTS make duplicate input possible.
  if [[ -f "$file" ]]; then
    while IFS= read -r entry; do
      for candidate in "${all[@]}"; do
        if [[ "$candidate" == "$entry" && -z "${emitted[$entry]:-}" ]]; then
          printf '%s\n' "$entry"
          emitted[$entry]=1
          break
        fi
      done
    done < "$file"
  fi

  for candidate in "${all[@]}"; do
    if [[ -n "${emitted[$candidate]:-}" ]]; then
      continue
    fi
    printf '%s\n' "$candidate"
    emitted[$candidate]=1
  done
  return 0
}

ct_parse_worktrees() {
  local line worktree branch
  worktree=""
  branch=""

  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        worktree="${line#worktree }" ;;
      "branch refs/heads/"*)
        branch="${line#branch refs/heads/}" ;;
      "detached")
        branch="(detached)" ;;
      "")
        if [[ -n "$worktree" ]]; then
          printf '%s\t%s\n' "$worktree" "$branch"
        fi
        worktree=""
        branch=""
        ;;
    esac
  done

  if [[ -n "$worktree" ]]; then
    printf '%s\t%s\n' "$worktree" "$branch"
  fi
  return 0
}

ct_parse_tmux() {
  local line
  while IFS= read -r line; do
    printf '%s\t%s\n' "${line%%:*}" "${line#*:}"
  done
  return 0
}

ct_parse_cmux() {
  jq -r '.windows[]? | .workspaces[]? | [.ref, .title] | @tsv'
}
