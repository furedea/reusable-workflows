#!/usr/bin/env bash
# Fails when an ADR that is accepted at the base commit is removed or renumbered, or when its body
# changed. The body is everything after the front matter; front-matter changes are allowed. The ADRs
# are matched by the NNNN file-name prefix, so a rename that keeps the prefix does not hide a change.
#
# Violation lines never repeat file content (see check_front_matter.sh).
set -euo pipefail

main() {
  local _adr_dir=${1:?usage: check_accepted_body.sh <adr-dir> <base-sha>}
  local _base_sha=${2:?usage: check_accepted_body.sh <adr-dir> <base-sha>}
  local _base_file _id _head_file _head_files _failed=0

  git cat-file -e "$_base_sha^{commit}" || {
    echo "base commit is not available: fetch the full history" >&2
    exit 1
  }

  while IFS= read -r _base_file; do
    [[ $(base_status "$_base_sha" "$_base_file") == accepted ]] || continue
    _id=$(basename "$_base_file")
    _id=${_id%%_*}
    _head_files=("$_adr_dir/${_id}"_*.md)
    if [[ ! -f ${_head_files[0]} ]]; then
      printf '%s: an accepted ADR was removed or renumbered; keep it and write a new ADR that supersedes it\n' "${_base_file//[^[:print:]]/?}" >&2
      _failed=1
      continue
    fi
    for _head_file in "${_head_files[@]}"; do
      if [[ $(body_of_base "$_base_sha" "$_base_file" | git hash-object --stdin) != "$(body_of_file "$_head_file" | git hash-object --stdin)" ]]; then
        printf '%s: the body of an accepted ADR changed; write a new ADR that supersedes it\n' "${_head_file//[^[:print:]]/?}" >&2
        _failed=1
      fi
    done
  done < <(base_adr_files "$_base_sha" "$_adr_dir")
  ((_failed == 0)) || exit 1
  echo "accepted ADR bodies unchanged"
}

# Prints the paths of the ADRs (NNNN_*.md directly in the directory) at the base commit.
base_adr_files() {
  git ls-tree --name-only "$1" -- "$2/" | grep -E "^$2/[0-9]{4}_[^/]+\.md$" || true
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
