#!/usr/bin/env bash
# Fails when the body of an ADR changed although its version at the base commit has status accepted.
# The body is everything after the front matter; front-matter changes are allowed. An ADR is matched
# to its base version by the NNNN file-name prefix, so a rename does not hide a body change.
#
# Violation lines never repeat file content (see check_front_matter.sh).
set -euo pipefail

main() {
  local _adr_dir=${1:?usage: check_accepted_body.sh <adr-dir> <base-sha>}
  local _base_sha=${2:?usage: check_accepted_body.sh <adr-dir> <base-sha>}
  local _head_file _base_file _id _failed=0

  git cat-file -e "$_base_sha^{commit}" || {
    echo "base commit is not available: fetch the full history" >&2
    exit 1
  }

  for _head_file in "$_adr_dir"/[0-9][0-9][0-9][0-9]_*.md; do
    [[ -f $_head_file ]] || continue
    _id=$(basename "$_head_file")
    _id=${_id%%_*}
    _base_file=$(base_file_for_id "$_base_sha" "$_adr_dir" "$_id")
    [[ -n $_base_file ]] || continue
    [[ $(base_status "$_base_sha" "$_base_file") == accepted ]] || continue
    if [[ $(body_of_base "$_base_sha" "$_base_file" | git hash-object --stdin) != "$(body_of_file "$_head_file" | git hash-object --stdin)" ]]; then
      printf '%s: the body of an accepted ADR changed; write a new ADR that supersedes it\n' "$_head_file" >&2
      _failed=1
    fi
  done
  ((_failed == 0)) || exit 1
  echo "accepted ADR bodies unchanged"
}

# Prints the base path of the ADR with the given ID, or nothing when it is absent or ambiguous.
base_file_for_id() {
  local _matches
  _matches=$(git ls-tree --name-only "$1" -- "$2/" | grep -E "^$2/$3_[^/]+\\.md$" || true)
  [[ $(printf '%s' "$_matches" | grep -c .) == 1 ]] && printf '%s\n' "$_matches"
  return 0
}

base_status() {
  git show "$1:$2" | yq --front-matter=extract '.status' 2>/dev/null || true
}

body_of_base() { git show "$1:$2" | body_of_stream; }

body_of_file() { body_of_stream <"$1"; }

# Prints the lines after the closing front-matter delimiter, or nothing when there is no front matter.
body_of_stream() {
  awk 'NR == 1 { if ($0 != "---") exit; next } closed { print; next } $0 == "---" { closed = 1 }'
}

main "$@"
