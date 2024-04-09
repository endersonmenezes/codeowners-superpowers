# codeowners-superpowers
A GitHub Action that powers the CODEOWNERS.

## Example

```yaml
  - name: Verify CODEOWNERs and Changed Files
    uses: endersonmenezes/codeowners-superpowers@main
    with:
        super_power: "require-all-codeowners"
        gh-token: ${{ steps.app-token.outputs.token }}
        pr_number: ${{ github.event.number }}
        owner_and_repository: ${{ github.repository }}
```

## Available Super Powers

- require-all-codeowners

### require-all-codeowners

This Superpower will check if all codeowners necessary have been approved in the PR. 

Based on: [this discussion](https://github.com/isaacs/github/issues/1205)
