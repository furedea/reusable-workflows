# reusable-workflows

Reusable GitHub Actions workflows (`on: workflow_call`) shared by furedea repositories.

## Workflows in this repository

Shared workflows, called from the `ci.yml` of other repositories (each has a section below):

- `claude-review.yml`
- `codex-review.yml`
- `gha-lint.yml`
- `dependency-review.yml`
- `nix-lint.yml`
- `nix-check.yml`
- `release-pr.yml`
- `release-publish.yml`

A composite action, called as a step: `.github/actions/nix-setup` (see "nix-setup (composite action)" below).

Workflows for this repository only, not meant to be called from elsewhere:

- `ci.yml` calls the shared workflows above and runs `nix-setup`, so that a pull request here tests its own
  versions, and gates merging on `all-green`.
- `release-please.yml` creates release PRs and `vX.Y.Z` tags by calling `release-pr.yml`.

Workflow file names use kebab-case, as GitHub Actions and release-please-action do (`ls-lint` enforces it).

## Calling a shared workflow

Call a shared workflow from another repository with a full commit SHA and the release tag as the comment:

```yaml
uses: furedea/reusable-workflows/.github/workflows/<name>.yml@<full-commit-sha> # vX.Y.Z
```

release-please tags every release of this repository as `vX.Y.Z`, and Renovate opens a pull request in each
caller that moves the pinned SHA and the comment to the new release.

Do not write `# main` in the comment. zizmor's `ref-version-mismatch` audit fails when the SHA is no longer the
commit that the comment names, so every time `main` moves, the `gha-lint` of every caller would break. A release
tag does not move, so nothing happens in the callers until the next release.

Releases are made by `release-please.yml`: on every push to `main` it opens or updates a release PR from the
Conventional Commits, and merging that PR creates the tag and the GitHub release. The settings are in `release-please-config.json` and
`.release-please-manifest.json`, the default names of release-please-action. The workflow signs in as a
GitHub App, so that the release PR triggers CI; a PR opened with `GITHUB_TOKEN` does not. The App needs the
Contents, Issues and Pull requests permissions (read and write) and must be installed on this repository, which
needs the variable `RELEASE_APP_CLIENT_ID` (the App's Client ID) and the secret `RELEASE_APP_PRIVATE_KEY`. The workflow mints a token for
this repository only with `actions/create-github-app-token`.

## claude-review.yml

Reviews every same-repository pull request with Claude Code. It posts P0 to P3 findings as inline comments
and a summary comment, and fails when there is at least one P0 or P1 finding. Fork pull requests are skipped
because secrets are not passed to them. Pull requests opened by bots other than `furedea-agent` (for example
Renovate) are not reviewed, because the action rejects other bots. The workflow itself skips these cases, and
runs only for `pull_request` events, so callers need no `if`.

Call it from the `ci.yml` of another repository. Pin it to a full commit SHA, pass the secret, and add the job
to `all-green`'s `needs`:

```yaml
jobs:
    claude-review:
        uses: furedea/reusable-workflows/.github/workflows/claude-review.yml@<full-commit-sha> # <ref>
        permissions:
            contents: read
            pull-requests: write
        secrets:
            claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}

    all-green:
        if: always()
        needs: [claude-review]
        runs-on: ubuntu-latest
        permissions: {}
        steps:
            - name: Fail if any prerequisite did not succeed
              if: contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled') || contains(needs.*.result, 'skipped')
              run: exit 1
```

The caller needs the repository secret `CLAUDE_CODE_OAUTH_TOKEN`.

## codex-review.yml

Asks the Codex GitHub connector to review every same-repository pull request, on open and on every push, and
waits for its result. Codex ignores review requests from bots and charges repository-wide automatic reviews to
credits, so the workflow posts `@codex review` with the repository owner's token; the review then runs on the
owner's ChatGPT plan. The job reads the `codex-review-state` that Codex records in its summary comment and
fails when the review of the head commit has unresolved findings, when Codex reports a failure (for example
usage limits), or when no review arrives within 20 minutes. It skips the same pull requests as
`claude-review.yml`.

```yaml
jobs:
    codex-review:
        uses: furedea/reusable-workflows/.github/workflows/codex-review.yml@<full-commit-sha> # <ref>
        permissions: {}
        secrets:
            codex_review_token: ${{ secrets.CODEX_REVIEW_TOKEN }}
```

Add `codex-review` to `all-green`'s `needs`. The caller needs the repository secret `CODEX_REVIEW_TOKEN`: a
fine-grained token of the owner with only Pull requests read and write. In the Codex settings, keep the
repository's automatic review on "Follow personal preferences".

## gha-lint.yml

Lints the workflows with actionlint (with shellcheck and pyflakes) and zizmor. It takes no inputs.

```yaml
jobs:
    gha-lint:
        uses: furedea/reusable-workflows/.github/workflows/gha-lint.yml@<full-commit-sha> # <ref>
        permissions:
            actions: read
            contents: read
```

Add `gha-lint` to `all-green`'s `needs`.

## dependency-review.yml

Fails a pull request that adds a dependency with a vulnerability at or above `fail-on-severity` (default
`high`). The review runs only for `pull_request` events of public repositories; in every other case the
caller job still succeeds, so callers need no `if`.

```yaml
jobs:
    dependency-review:
        uses: furedea/reusable-workflows/.github/workflows/dependency-review.yml@<full-commit-sha> # <ref>
        permissions:
            contents: read
        with:
            fail-on-severity: high # optional
```

Add `dependency-review` to `all-green`'s `needs`.

## nix-lint.yml

Checks Nix files with nixfmt (tracked `*.nix` files), statix, and deadnix (`--fail`).

```yaml
jobs:
    nix-lint:
        uses: furedea/reusable-workflows/.github/workflows/nix-lint.yml@<full-commit-sha> # <ref>
        permissions:
            contents: read
```

Add `nix-lint` to `all-green`'s `needs`.

## nix-check.yml

Runs `nix flake check -L` to build the runner's own checks, then `nix flake check --all-systems --no-build` to
evaluate every system's outputs without building other systems' checks on the Linux runner. It takes no inputs
and uses no cache, because a cold run takes 40 to 70 seconds; add a cache only when a repository gets slow.

```yaml
jobs:
    nix-check:
        uses: furedea/reusable-workflows/.github/workflows/nix-check.yml@<full-commit-sha> # <ref>
        permissions:
            contents: read
```

Add `nix-check` to `all-green`'s `needs`.

## release-pr.yml and release-publish.yml

Together they release a repository with release-please, draft releases and immutable releases. A caller's
`release.yml` runs on every push to `main`, in three jobs. The workflows only draft, attest and publish; the
releases become immutable only when the caller enables the repository setting "Enable release immutability"
(Settings > General > Releases). Enable it before the first release.

1. `release-pr` (`release-pr.yml`) opens or updates the release PR. When the PR is merged it creates the tag and a
   **draft** release, and outputs `release_created` and `tag_name`.
2. `build` (the caller's own job) builds the artifacts on the tag and uploads them as one workflow artifact.
3. `release-publish` (`release-publish.yml`) checks that the tag points to the commit of the run and that the
   release is still a draft, attests every file of the artifact, uploads the files to the draft and publishes it.

The build stays in the caller because each repository builds differently; only the release steps are shared.
The files in the artifact are exactly the release assets: put checksums and every other asset there too. The
artifact must be flat, with regular files only, no subdirectories and no hidden files (upload-artifact drops hidden
files unless `include-hidden-files` is set, and `release-publish.yml` would skip them), because each entry is attested and passed to
`gh release upload` as an asset (upload-artifact keeps the directories below a wildcard, so `dist/*` must match
files, not directories). The
attestation is signed by `release-publish.yml` at the pinned SHA, which is the builder identity to verify.

```yaml
name: Release

on:
    push:
        branches:
            - main
    workflow_dispatch: # recovery of a stuck draft, run on the tag itself
        inputs:
            tag_name:
                description: Draft release tag to build and publish; run this workflow on the same tag
                required: true
                type: string

permissions: {}

concurrency:
    group: release-${{ github.repository }}
    cancel-in-progress: false

jobs:
    release-pr:
        if: github.event_name == 'push'
        uses: furedea/reusable-workflows/.github/workflows/release-pr.yml@<full-commit-sha> # <ref>
        permissions: {}
        with:
            app-client-id: ${{ vars.RELEASE_APP_CLIENT_ID }}
        secrets:
            app_private_key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

    build:
        needs: release-pr
        if: ${{ !cancelled() && (needs.release-pr.outputs.release_created == 'true' || github.event_name == 'workflow_dispatch') }}
        runs-on: ubuntu-24.04
        timeout-minutes: 20
        permissions:
            contents: read
        steps:
            - uses: actions/checkout@<full-commit-sha> # <ref>
              with:
                  persist-credentials: false
                  ref: ${{ needs.release-pr.outputs.tag_name || inputs.tag_name }}
            # ... build and test, writing the release assets to dist/ ...
            - uses: actions/upload-artifact@<full-commit-sha> # <ref>
              with:
                  name: release-artifacts
                  path: dist/*
                  if-no-files-found: error

    release-publish:
        needs: [release-pr, build]
        if: ${{ !cancelled() && needs.build.result == 'success' }}
        uses: furedea/reusable-workflows/.github/workflows/release-publish.yml@<full-commit-sha> # <ref>
        permissions:
            contents: write
            id-token: write
            attestations: write
        with:
            tag-name: ${{ needs.release-pr.outputs.tag_name || inputs.tag_name }}
```

`release-publish.yml` stops when the tag does not point to the commit of the run. This happens when the
release PR's merge commit is not the commit of the run that creates the tag: concurrency keeps only one pending run
per group, so a later push can cancel the run of the merge commit, and the next run then tags the merge commit
while `GITHUB_SHA` is the later one. Re-running the job does not help. Recover the draft by dispatching the
workflow on the tag itself, which makes `GITHUB_SHA` the tagged commit (`workflow_dispatch` in the example):

```bash
gh workflow run release.yml --ref vX.Y.Z -f tag_name=vX.Y.Z
```

The attestation step needs a public repository, or GitHub Enterprise Cloud for a private or internal one
([attest-build-provenance](https://github.com/actions/attest-build-provenance#usage)). On GitHub Free, Pro or Team,
a private repository cannot use `release-publish.yml`.

The caller's release-please config must set `"draft": true` and `"force-tag-creation": true` on the package.
Without `draft`, release-please publishes the release at once and `release-publish.yml` stops at its draft check.
Without `force-tag-creation`, GitHub creates no git tag for a draft, so the `build` checkout of the tag and the
tag check of `release-publish.yml` both fail.

Only a single package at the root path (`"."`) is supported. For any other path, or for several packages,
release-please emits path-prefixed outputs (`<path>--release_created`), which `release-pr.yml` does not expose, so
the release would stay a draft.

`release-pr.yml` takes `config-file` and `manifest-file` (defaults `release-please-config.json` and
`.release-please-manifest.json`); `release-publish.yml` takes `artifact-name` (default `release-artifacts`).

The release GitHub App, not `GITHUB_TOKEN` or a personal access token, opens the release PR, so that it triggers
CI. The caller needs the variable `RELEASE_APP_CLIENT_ID` and the secret `RELEASE_APP_PRIVATE_KEY`, and the App
must be installed on the repository with Contents, Issues and Pull requests permissions (read and write).

## nix-setup (composite action)

`.github/actions/nix-setup` installs Nix (`install-nix-action`, the same pinned SHA as `nix-check.yml` and
`nix-lint.yml`) and restores the Nix store cache (`cache-nix-action`). Use it in a job that runs the repository's
tools from its flake dev shell, so that CI and a local shell use the versions in `flake.lock`.

The cache key is `<key-prefix>-<runner.os>-<runner.arch>-<hash of every .nix file and every flake.lock>`, so a change to a
file that `flake.nix` imports also changes the key (the action saves only when the exact key is absent). On a miss, the
newest cache with the same prefix, OS and architecture is restored and only the difference is built. The store is
garbage-collected to 5 GiB before it is saved, so that it stays below GitHub's 10 GiB cache quota per repository.

| Input        | Default                       | Meaning                                                                                                 |
| ------------ | ----------------------------- | ------------------------------------------------------------------------------------------------------- |
| `key-prefix` | `nix`                         | Prefix of the cache key; use a different one for jobs whose store content differs                       |
| `save`       | `github.event_name == 'push'` | Save the cache at the end of the job; pull requests only restore (a pull request cache is not reusable) |

Jobs of one workflow that share a key race to save it, and only one wins. Pass `save: false` to every job but one
if the saving job should be a fixed one.

```yaml
defaults:
    run:
        shell: nix develop --command bash -eo pipefail {0}

jobs:
    test:
        runs-on: ubuntu-24.04
        timeout-minutes: 20
        permissions:
            contents: read
        steps:
            - uses: actions/checkout@<full-commit-sha> # <ref>
              with:
                  persist-credentials: false

            # `defaults.run.shell` applies to `run` steps only, so this step needs no Nix yet.
            - uses: furedea/reusable-workflows/.github/actions/nix-setup@<full-commit-sha> # <ref>

            - run: pytest
```

Pin the action to a full commit SHA like the workflows. The dev shell must exist for the runner's system
(`x86_64-linux`).

`nix-check.yml` and `nix-lint.yml` do not use it: a reusable workflow resolves `./.github/actions/...` in the
caller's repository, and a pinned `furedea/reusable-workflows/...@<sha>` cannot name its own release.

## Pinned tool versions

Every tool these workflows run is pinned so that its content cannot change, not only its version string.
Renovate updates each pin through the `customManagers` in `renovate.json`:

- `nix-lint.yml` and `gha-lint.yml`: one nixpkgs revision in the job env `NIXPKGS_REV` (the same value in both
  files). It provides nixfmt, statix, deadnix and actionlint, and a nixpkgs revision fixes every input by hash.
  The nixpkgs actionlint bundles shellcheck and pyflakes. It is run with `nix run` from this revision instead of
  a release asset download, because a release asset is not checksum-verified and can be replaced. Renovate moves
  the revision in both files to the head of `nixos-unstable` in one pull request.
- `gha-lint.yml`: zizmor `version: 1.32.0`. The pinned SHA of `zizmor-action` carries a lockfile with hashes, so
  this version fixes the content of zizmor as well.
- Nix and the Claude CLI are pinned by the SHA of the action that installs them (`install-nix-action` v31.11.3
  installs Nix 2.35.4, `claude-code-action` v1.0.268 installs Claude CLI 2.1.318). They move up together with the
  action when Renovate updates it.
- `runs-on: ubuntu-24.04` in every workflow instead of `ubuntu-latest`. GitHub provides the two newest Ubuntu
  LTS releases, and its `ubuntu-latest` migration notice advises pinning 24.04. `ubuntu-26.04` is not used because
  the pinned actionlint 1.7.12 does not know the label (furedea/reusable-workflows#17).
