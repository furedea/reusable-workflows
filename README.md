# reusable-workflows

Reusable GitHub Actions workflows (`on: workflow_call`) shared by furedea repositories.

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
