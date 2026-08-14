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

# Load CT_ROOTS: generic defaults, then the user's config file if present.
# Lives here rather than inline in bin/ct so ct-alfred reads the same values.
ct_load_config() {
  CT_ROOTS=("$HOME/dev" "$HOME/src" "$HOME/code" "$HOME/projects")
  if [[ -f "$HOME/.config/ct/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.config/ct/config.sh"
  fi
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

  # `|| [[ -n "$line" ]]` processes a final line with no trailing newline.
  # Without it `read` populates $line but returns non-zero, the loop body never
  # runs for that line, and the post-loop flush emits a record with an empty
  # branch — silent corruption rather than an error.
  while IFS= read -r line || [[ -n "$line" ]]; do
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
  # Splits on the FIRST colon. tmux permits colons in session names, so a
  # hand-created `foo:bar` would mis-pair; ct only ever creates sessions from
  # `[a-z0-9-]` slugs, and a mis-paired name simply fails to match any slug.
  # `|| [[ -n "$line" ]]` processes a final line with no trailing newline,
  # which would otherwise be dropped silently.
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\t%s\n' "${line%%:*}" "${line#*:}"
  done
  return 0
}

ct_parse_cmux() {
  jq -r '.windows[]? | .workspaces[]? | [.ref, .title] | @tsv'
}

ct_trunk_ref() {
  local repo="$1" head
  head="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)" || {
    echo "Error: origin/HEAD is not set in $repo." >&2
    echo "Fix with: git -C $repo remote set-head origin -a" >&2
    return 1
  }
  printf 'origin/%s\n' "${head#refs/remotes/origin/}"
}

ct_branch_state() {
  local repo="$1" slug="$2"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$slug"; then
    printf 'local\n'
    return 0
  fi

  # Side effect worth knowing about: this is a network round trip whenever the
  # branch is not already local. Callers should treat ct_branch_state as a
  # remote-touching operation, not a cheap local query.
  #
  # A failed fetch and a branch that genuinely does not exist on origin both
  # end up as `none`. That means a network blip can make ct_add_worktree cut a
  # fresh branch off trunk instead of tracking an existing remote one.
  # Distinguishing the two needs `git ls-remote` error parsing, which is not
  # worth the complexity here.
  git -C "$repo" fetch --quiet origin "$slug" 2>/dev/null || true

  if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$slug"; then
    printf 'remote\n'
    return 0
  fi

  printf 'none\n'
}

ct_add_worktree() {
  local repo="$1" slug="$2"
  local path state trunk wt registered
  path="$(ct_worktree_path "$repo" "$slug")"

  # Ask git whether this is a registered worktree rather than testing `-d`.
  # A bare -d would report success for a stray directory left behind by an
  # interrupted `git worktree add`, handing the caller a broken worktree and
  # a "ready" message.
  #
  # Compared with `-ef` (device+inode), not a string/regex match: git
  # canonicalizes worktree paths when it registers them (e.g. resolving
  # /tmp -> /private/tmp on macOS), so a literal match against our own
  # unresolved $path can miss a real, already-registered worktree.
  registered=0
  while IFS= read -r wt; do
    if [[ "$wt" -ef "$path" ]]; then
      registered=1
      break
    fi
  done < <(git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p')

  if [[ "$registered" -eq 1 ]]; then
    echo "Worktree already exists: $path"
    return 0
  fi

  # An unregistered directory at $path is refused explicitly rather than left
  # to `git worktree add` below: git only fails loudly against a *non-empty*
  # stray directory. An empty one (e.g. left by an interrupted `git worktree
  # add` that got no further than mkdir) is silently accepted as a checkout
  # target, which would defeat the point of the registration check above.
  if [[ -e "$path" ]]; then
    echo "Error: $path exists but is not a registered worktree." >&2
    echo "Remove it manually and retry." >&2
    return 1
  fi

  mkdir -p "$(dirname "$path")"
  state="$(ct_branch_state "$repo" "$slug")"

  case "$state" in
    local)
      echo "Reusing local branch $slug"
      git -C "$repo" worktree add "$path" "$slug"
      ;;
    remote)
      echo "Tracking origin/$slug"
      git -C "$repo" worktree add --track -b "$slug" "$path" "origin/$slug"
      ;;
    none)
      trunk="$(ct_trunk_ref "$repo")"
      echo "Creating branch $slug off $trunk"
      # --no-track because the start point is a remote-tracking ref, and git's
      # default branch.autoSetupMerge would make origin/<trunk> the new
      # branch's upstream. The first `git push` from the worktree then fails
      # under the default push.default=simple, and the fix git suggests
      # (`git push origin HEAD:<trunk>`) puts the task's commits on the default
      # branch. It also makes `git status` read "ahead of origin/<trunk>".
      # With no upstream, git instead suggests `git push --set-upstream origin
      # <slug>`, which is what was wanted. The `remote` case above keeps
      # --track: there the upstream genuinely is the same-named branch.
      git -C "$repo" worktree add --no-track -b "$slug" "$path" "$trunk"
      ;;
  esac
}

ct_claude_project_dir() {
  local path="$1" escaped
  escaped="$(printf '%s' "$path" | tr '/.' '--')"
  printf '%s/projects/%s\n' "${CT_CLAUDE_HOME:-$HOME/.claude}" "$escaped"
}

ct_claude_cmd() {
  local dir
  dir="$(ct_claude_project_dir "$1")"
  if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
    printf 'claude --continue\n'
  else
    printf 'claude\n'
  fi
}

# Join worktree, tmux, and cmux state into one task row per worktree.
# Each argument is a file (or process substitution) holding that tool's
# already-parsed output.
ct_join_task_state() {
  local wt_file="$1" tmux_file="$2" cmux_file="$3"
  local path branch root slug repo live

  while IFS=$'\t' read -r path branch; do
    [[ -n "$path" ]] || continue

    root="$(dirname "$path")"
    case "$root" in
      *-wt) ;;
      *) continue ;;
    esac

    slug="$(basename "$path")"
    repo="${root%-wt}"
    live="worktree"

    # Matching is on slug alone, so two tasks with the same slug in different
    # repos would each show the other's live markers. That state is already
    # unreachable through ct: tmux session names are a global namespace and
    # ct_ensure_tmux refuses a same-named session whose path differs, so the
    # second `ct new` fails before such a pair can exist. Disambiguating by
    # path was considered and rejected — git reports canonicalized paths
    # (/var -> /private/var) while tmux reports the literal one, so a string
    # compare would introduce the very bug class that has already cost this
    # project two fix rounds, and cmux's tree JSON carries no path at all.
    if cut -f1 < "$tmux_file" | grep -Fxq -- "$slug"; then
      live="$live/tmux"
    fi
    if cut -f2 < "$cmux_file" | grep -Fxq -- "$slug"; then
      live="$live/cmux"
    fi

    printf '%s\t%s\t%s\t%s\n' "$slug" "$repo" "$branch" "$live"
  done < "$wt_file"
  return 0
}

# Returns 0 when the worktree is safe to remove, 1 otherwise, printing why.
#
# Both git calls are checked for failure and neither swallows stderr. This is
# the one function whose entire job is preventing lost work, so "git could not
# answer" must not be indistinguishable from "nothing to report" -- silently
# reporting clean is exactly the wrong direction to fail in.
ct_worktree_clean() {
  local path="$1" dirty=0 porcelain unpushed

  if ! porcelain="$(git -C "$path" status --porcelain)"; then
    echo "could not read git status in $path; refusing to call it clean"
    return 1
  fi
  if [[ -n "$porcelain" ]]; then
    echo "uncommitted or untracked changes"
    dirty=1
  fi

  # Commits on this worktree's HEAD that no remote-tracking branch contains.
  # Captured whole and truncated afterwards with a here-string: piping git into
  # `head -5` would let head close the pipe on a long list, and under pipefail
  # the resulting SIGPIPE (141) would read as a git failure.
  if ! unpushed="$(git -C "$path" log --oneline HEAD --not --remotes)"; then
    echo "could not list unpushed commits in $path; refusing to call it clean"
    return 1
  fi
  if [[ -n "$unpushed" ]]; then
    echo "commits not on origin:"
    head -5 <<< "$unpushed"
    dirty=1
  fi

  return "$dirty"
}
