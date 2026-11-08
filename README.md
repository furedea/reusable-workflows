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

Workflows for this repository only, not meant to be called from elsewhere:

- `ci.yml` calls the shared workflows above, so that a pull request here tests its own versions, and gates
  merging on `all-green`.
- `codeql.yml` runs CodeQL on public repositories.
- `release_please.yml` creates release PRs and `vX.Y.Z` tags.

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

Releases are made by `release_please.yml`: on every push to `main` it opens or updates a release PR from the
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

Lints the workflows with actionlint (with shellcheck and pyflakes) and zizmor. The optional input
`workflow-template-dir` names a directory of workflow templates (`*.yml`) that are checked as well.

```yaml
jobs:
    gha-lint:
        uses: furedea/reusable-workflows/.github/workflows/gha-lint.yml@<full-commit-sha> # <ref>
        permissions:
            actions: read
            contents: read
        with:
            workflow-template-dir: templates # optional
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
evaluate every system's outputs without building other systems' checks on the Linux runner. It uses no cache,
because a cold run takes 40 to 70 seconds; add a cache only when a repository gets slow.

```yaml
jobs:
    nix-check:
        uses: furedea/reusable-workflows/.github/workflows/nix-check.yml@<full-commit-sha> # <ref>
        permissions:
            contents: read
        with:
            all-systems: true # optional, default true
```

The input `all-systems` (boolean, default `true`) controls the second step. Set it to `false` for a flake that
uses import-from-derivation (for example `builtins.pathExists` on a derivation output): evaluating its
foreign-system outputs requires building them, so `--no-build` fails on the Linux runner for its darwin outputs
(seen in furedea/agent-harness#195 and furedea/dotfiles#405). With `false`, only `nix flake check -L` runs.

Add `nix-check` to `all-green`'s `needs`.

## Pinned tool versions

Every tool these workflows run is pinned to an exact version, so a run does not change when an upstream
`latest` moves. Renovate updates each pin through the `customManagers` in `renovate.json`:

- `gha-lint.yml`: actionlint (`version: 1.7.12`) and zizmor (`version: 1.32.0`), from their GitHub releases.
- `nix-lint.yml`: one nixpkgs revision in the job env `NIXPKGS_REV`, which provides nixfmt, statix and deadnix.
  Renovate moves it to the head of `nixos-unstable`.
- Nix and the Claude CLI are pinned by the SHA of the action that installs them (`install-nix-action` v31.11.3
  installs Nix 2.35.4, `claude-code-action` v1.0.268 installs Claude CLI 2.1.318). They move up together with the
  action when Renovate updates it.
- `runs-on: ubuntu-26.04` in every workflow instead of `ubuntu-latest`. `.github/actionlint.yaml` allows the label
  until actionlint knows it.
