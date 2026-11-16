#!/usr/bin/env bash
# Checks the front matter of the ADRs in a directory against the fixed shape of ADR-0025 of
# furedea/agent-config. Prints one line per violation to stderr and exits 1 when there is one.
#
# The ADR files are untrusted input: a violation line never repeats file content, so that a file
# cannot forge workflow commands (lines starting with "::") in the log.
set -euo pipefail

readonly ID_PATTERN='^"([a-z0-9._-]+/)?ADR-[0-9]{4}"$'
readonly AMENDMENT_PATTERN='^"[0-9]{4}-[0-9]{2}-[0-9]{2}: .+"$'
readonly DATE_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
readonly FILE_NAME_PATTERN='^[0-9]{4}_[A-Za-z0-9_.-]+\.md$'
readonly ID_LIST_KEYS=(supersedes superseded-by partly-superseded-by related)
readonly TEXT_KEYS=(decision-makers consulted informed)

violation_count=0
seen_ids=$'\n'
graph_lines=''

main() {
  local _adr_dir=${1:?usage: check_front_matter.sh <adr-dir>}
  local _adr_file _found=0

  for _adr_file in "$_adr_dir"/[0-9][0-9][0-9][0-9]_*.md; do
    [[ -f $_adr_file ]] || continue
    _found=1
    check_adr "$_adr_file"
  done
  ((_found == 1)) || report "$_adr_dir" "no ADR file NNNN_*.md found"

  check_graph
  ((violation_count == 0)) || exit 1
  echo "ADR front matter OK"
}

# The path is untrusted too (a file name may contain a newline), so control characters become "?".
report() {
  printf '%s: %s\n' "${1//[^[:print:]]/?}" "$2" >&2
  violation_count=$((violation_count + 1))
}

front_matter_raw() { yq --front-matter=extract "$1" "$2"; }

front_matter_json() { yq --front-matter=extract -o=json -I=0 "$1" "$2"; }

check_adr() {
  local _adr_file=$1 _name _id
  _name=$(basename "$_adr_file")
  if [[ ! $_name =~ $FILE_NAME_PATTERN ]]; then
    report "$_adr_file" "invalid file name"
    return
  fi
  _id=${_name%%_*}
  if [[ $seen_ids == *$'\n'"$_id"$'\n'* ]]; then
    report "$_adr_file" "duplicate ID $_id"
    return
  fi
  seen_ids+="$_id"$'\n'

  local _before=$violation_count
  check_front_matter_shape "$_adr_file"
  ((violation_count == _before)) || return 0
  check_supersession_keys "$_adr_file"
  collect_graph "$_adr_file" "$_id"
}

has_delimiters() {
  awk 'NR == 1 { if ($0 != "---") exit 1; next } $0 == "---" { found = 1; exit } END { exit !found }' "$1"
}

check_front_matter_shape() {
  local _adr_file=$1 _key
  if ! has_delimiters "$_adr_file"; then
    report "$_adr_file" "front matter missing"
    return
  fi
  if [[ $(front_matter_raw tag "$_adr_file" 2>/dev/null) != '!!map' ]]; then
    report "$_adr_file" "front matter is not a valid YAML mapping"
    return
  fi

  while IFS= read -r _key; do
    case $_key in
      status | date | amended | supersedes | superseded-by | partly-superseded-by | related | decision-makers | consulted | informed) ;;
      *) report "$_adr_file" "unknown key" ;;
    esac
  done < <(front_matter_raw 'keys | .[]' "$_adr_file")

  require_key "$_adr_file" status
  require_key "$_adr_file" date
  has_key "$_adr_file" status && check_status "$_adr_file"
  has_key "$_adr_file" date && check_date "$_adr_file"
  has_key "$_adr_file" amended && check_list "$_adr_file" amended "$AMENDMENT_PATTERN"
  for _key in "${ID_LIST_KEYS[@]}"; do
    has_key "$_adr_file" "$_key" && check_list "$_adr_file" "$_key" "$ID_PATTERN"
  done
  for _key in "${TEXT_KEYS[@]}"; do
    has_key "$_adr_file" "$_key" && check_text "$_adr_file" "$_key"
  done
  return 0
}

# True when the key is present, even with a null value, which the shape checks then reject.
has_key() {
  [[ $(front_matter_raw "has(\"$2\")" "$1") == true ]]
}

require_key() {
  has_key "$1" "$2" || report "$1" "missing key: $2"
}

check_status() {
  local _status
  [[ $(front_matter_raw '.status | tag' "$1") == '!!str' ]] || {
    report "$1" "invalid status"
    return
  }
  _status=$(front_matter_raw .status "$1")
  case $_status in
    proposed | accepted | rejected | deprecated | superseded) ;;
    *) report "$1" "invalid status" ;;
  esac
}

check_date() {
  local _tag
  _tag=$(front_matter_raw '.date | tag' "$1")
  if [[ $_tag != '!!str' && $_tag != '!!timestamp' ]] || [[ ! $(front_matter_raw .date "$1") =~ $DATE_PATTERN ]]; then
    report "$1" "invalid date, expected YYYY-MM-DD"
  fi
}

# A list key must be a non-empty sequence whose every element matches the pattern (as JSON text).
check_list() {
  local _adr_file=$1 _key=$2 _pattern=$3 _element _count=0
  if [[ $(front_matter_raw ".[\"$_key\"] | tag" "$_adr_file") != '!!seq' ]]; then
    report "$_adr_file" "invalid $_key, expected a list"
    return
  fi
  while IFS= read -r _element; do
    _count=$((_count + 1))
    [[ $_element =~ $_pattern ]] || report "$_adr_file" "invalid $_key element"
  done < <(front_matter_json ".[\"$_key\"][]" "$_adr_file")
  ((_count > 0)) || report "$_adr_file" "invalid $_key, expected a non-empty list"
}

check_text() {
  local _adr_file=$1 _key=$2 _element _count=0
  case $(front_matter_raw ".[\"$_key\"] | tag" "$_adr_file") in
    '!!str')
      [[ $(front_matter_json ".[\"$_key\"]" "$_adr_file") != '""' ]] || report "$_adr_file" "invalid $_key, expected text"
      ;;
    '!!seq')
      while IFS= read -r _element; do
        _count=$((_count + 1))
        [[ $_element =~ ^\".+\"$ ]] || report "$_adr_file" "invalid $_key element"
      done < <(front_matter_json ".[\"$_key\"][]" "$_adr_file")
      ((_count > 0)) || report "$_adr_file" "invalid $_key, expected a non-empty list"
      ;;
    *) report "$_adr_file" "invalid $_key, expected text or a list of text" ;;
  esac
}

check_supersession_keys() {
  local _adr_file=$1 _status
  _status=$(front_matter_raw .status "$_adr_file")
  if [[ $_status == superseded ]] && ! has_key "$_adr_file" superseded-by; then
    report "$_adr_file" "status is superseded but superseded-by is missing"
  fi
  if [[ $_status != superseded ]] && has_key "$_adr_file" superseded-by; then
    report "$_adr_file" "superseded-by is present but status is not superseded"
  fi
}

# Adds the ADR as a node and each unprefixed reference as an edge; a prefixed ID (other
# repository) is not resolved.
collect_graph() {
  local _adr_file=$1 _id=$2 _key _element _target
  graph_lines+="N $_id $_adr_file"$'\n'
  for _key in "${ID_LIST_KEYS[@]}"; do
    has_key "$_adr_file" "$_key" || continue
    while IFS= read -r _element; do
      _target=${_element//\"/}
      [[ $_target == */* ]] && continue
      graph_lines+="E $_key $_id ${_target#ADR-}"$'\n'
    done < <(front_matter_json ".[\"$_key\"][]" "$_adr_file")
  done
}

check_graph() {
  local _line
  while IFS= read -r _line; do
    [[ -z $_line ]] || report "${_line%%|*}" "${_line#*|}"
  done < <(awk '
    $1 == "N" { path[$2] = $3 }
    $1 == "E" { edge[$2 " " $3 " " $4] = 1; edge_list[++edge_count] = $2 " " $3 " " $4 }
    END {
      for (i = 1; i <= edge_count; i++) {
        split(edge_list[i], e, " ")
        kind = e[1]; from = e[2]; to = e[3]
        if (!(to in path)) {
          print path[from] "|" kind " references a missing ADR-" to
        } else if (kind == "supersedes") {
          if (!edge["superseded-by " to " " from] && !edge["partly-superseded-by " to " " from])
            print path[from] "|supersedes ADR-" to ", which does not name it in superseded-by or partly-superseded-by"
        } else if (kind == "superseded-by" || kind == "partly-superseded-by") {
          if (!edge["supersedes " to " " from])
            print path[from] "|" kind " ADR-" to ", which does not name it in supersedes"
        }
      }
    }' <<<"$graph_lines")
}

main "$@"
