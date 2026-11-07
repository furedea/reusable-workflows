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

Runs `nix flake check -L --all-systems` on the repository's flake. `--all-systems` evaluates the outputs of
every declared system, so a flake that exposes only `aarch64-darwin` outputs is not skipped on the Linux
runner. Outputs of other systems are evaluated but not built. It takes no inputs and uses no cache, because a
cold run takes 40 to 70 seconds; add a cache only when a repository gets slow.

```yaml
jobs:
    nix-check:
        uses: furedea/reusable-workflows/.github/workflows/nix-check.yml@<full-commit-sha> # <ref>
        permissions:
            contents: read
```

Add `nix-check` to `all-green`'s `needs`.
