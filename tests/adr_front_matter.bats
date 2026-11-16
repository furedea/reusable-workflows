#!/usr/bin/env bats
# Tests of the adr-front-matter composite action's scripts. Run from the repository root with yq on PATH:
#   bats tests/adr_front_matter.bats

readonly ACTION=.github/actions/adr-front-matter
readonly FIXTURES=tests/adr-lint/fixtures

# The scripts need yq (mikefarah, v4). Outside the dev shell, fetch it from nixpkgs instead of failing.
setup_file() {
  command -v yq >/dev/null && return 0
  local _yq_out
  _yq_out=$(nix build --no-link --print-out-paths 'nixpkgs#yq-go')
  export PATH="$_yq_out/bin:$PATH"
}

assert_rejected() {
  run "$ACTION/check_front_matter.sh" "$FIXTURES/$1"
  [ "$status" -eq 1 ]
  [[ $output == *"$2"* ]]
}

@test "accepts conforming ADRs, including prefixed IDs of other repositories" {
  run "$ACTION/check_front_matter.sh" "$FIXTURES/valid"
  [ "$status" -eq 0 ]
}

@test "rejects an ADR without front matter" {
  assert_rejected missing-front-matter "front matter missing"
}

@test "rejects an unknown key" {
  assert_rejected unknown-key "unknown key"
}

@test "rejects a status outside the vocabulary" {
  assert_rejected invalid-status "invalid status"
}

@test "rejects a date that is not YYYY-MM-DD" {
  assert_rejected invalid-date "invalid date"
}

@test "rejects a missing required key" {
  assert_rejected missing-date "missing key: date"
}

@test "rejects a reference key that is not a list" {
  assert_rejected invalid-list "invalid related"
}

@test "rejects a reference that is not an ADR-NNNN ID" {
  assert_rejected invalid-reference "invalid related element"
}

@test "rejects duplicate IDs" {
  assert_rejected duplicate-id "duplicate ID 0001"
}

@test "rejects a reference to an ADR that does not exist" {
  assert_rejected missing-target "references a missing ADR-0099"
}

@test "rejects status superseded without superseded-by" {
  assert_rejected superseded-without-superseded-by "superseded-by is missing"
}

@test "rejects superseded-by on an ADR that is not superseded" {
  assert_rejected superseded-by-without-status "superseded-by is present but status is not superseded"
}

@test "rejects supersedes that the superseded ADR does not name" {
  assert_rejected supersedes-not-reciprocated "does not name it in superseded-by or partly-superseded-by"
}

@test "rejects superseded-by that the superseding ADR does not name" {
  assert_rejected superseded-by-not-reciprocated "does not name it in supersedes"
}

@test "rejects an optional key with an empty value" {
  assert_rejected null-value "invalid related"
}

@test "rejects a file name outside the convention" {
  cp "$FIXTURES/valid/0006_sixth_decision.md" "$BATS_TEST_TMPDIR/0006_Bad Name.md"
  run "$ACTION/check_front_matter.sh" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ $output == *"invalid file name"* ]]
}

@test "never lets a file name start a workflow command in the log" {
  local _name=$'0006_x\n::stop-commands::tok\n.md'
  cp "$FIXTURES/valid/0006_sixth_decision.md" "$BATS_TEST_TMPDIR/$_name"
  run "$ACTION/check_front_matter.sh" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ $output != *$'\n::'* && $output != ::* ]]
}

@test "never repeats file content in a violation line" {
  run "$ACTION/check_front_matter.sh" "$FIXTURES/unknown-key"
  [[ $output != *owner* ]]
}

@test "fails when the directory has no ADR" {
  run "$ACTION/check_front_matter.sh" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ $output == *"no ADR file"* ]]
}

# --- accepted ADR bodies (pull requests) ---

setup_repo() {
  cd "$BATS_TEST_TMPDIR"
  git init -q .
  git config user.name test
  git config user.email test@example.com
  git config commit.gpgsign false
  mkdir -p docs/adr
  printf -- '---\nstatus: %s\ndate: 2026-01-01\n---\n\n# Title\n\nBody.\n' "$1" >docs/adr/0001_decision.md
  git add .
  git commit -q -m base
  BASE=$(git rev-parse HEAD)
}

check_bodies() {
  run "$BATS_TEST_DIRNAME/../$ACTION/check_accepted_body.sh" docs/adr "$BASE"
}

@test "rejects a body change of an accepted ADR" {
  setup_repo accepted
  printf 'More.\n' >>docs/adr/0001_decision.md
  check_bodies
  [ "$status" -eq 1 ]
  [[ $output == *"0001_decision.md"* ]]
}

@test "allows a front-matter change of an accepted ADR" {
  setup_repo accepted
  printf -- '---\nstatus: accepted\ndate: 2026-02-02\namended: ["2026-02-02: note"]\n---\n\n# Title\n\nBody.\n' >docs/adr/0001_decision.md
  check_bodies
  [ "$status" -eq 0 ]
}

@test "allows a body change of an ADR that is not accepted at the base" {
  setup_repo proposed
  printf 'More.\n' >>docs/adr/0001_decision.md
  check_bodies
  [ "$status" -eq 0 ]
}

@test "rejects a body change that comes with a rename" {
  setup_repo accepted
  git mv docs/adr/0001_decision.md docs/adr/0001_renamed.md
  printf 'More.\n' >>docs/adr/0001_renamed.md
  check_bodies
  [ "$status" -eq 1 ]
}

@test "rejects the removal of an accepted ADR" {
  setup_repo accepted
  git rm -q docs/adr/0001_decision.md
  mkdir -p docs/adr
  printf -- '---\nstatus: proposed\ndate: 2026-01-01\n---\n\n# Other\n' >docs/adr/0002_other.md
  check_bodies
  [ "$status" -eq 1 ]
  [[ $output == *"removed or renumbered"* ]]
}

@test "rejects the renumbering of an accepted ADR" {
  setup_repo accepted
  git mv docs/adr/0001_decision.md docs/adr/0009_decision.md
  check_bodies
  [ "$status" -eq 1 ]
  [[ $output == *"removed or renumbered"* ]]
}

@test "never lets a base file name start a workflow command in the log" {
  setup_repo accepted
  git rm -q docs/adr/0001_decision.md
  mkdir -p docs/adr
  printf -- '---\nstatus: proposed\ndate: 2026-01-01\n---\n\n# Other\n' >docs/adr/0002_other.md
  check_bodies
  [[ $output != *$'\n::'* && $output != ::* ]]
}

@test "allows the removal of an ADR that is not accepted at the base" {
  setup_repo proposed
  git rm -q docs/adr/0001_decision.md
  check_bodies
  [ "$status" -eq 0 ]
}

@test "allows a new ADR" {
  setup_repo accepted
  printf -- '---\nstatus: proposed\ndate: 2026-01-01\n---\n\n# New\n' >docs/adr/0002_new.md
  check_bodies
  [ "$status" -eq 0 ]
}

@test "fails when the base commit is not available" {
  setup_repo accepted
  BASE=0000000000000000000000000000000000000000
  check_bodies
  [ "$status" -eq 1 ]
}
