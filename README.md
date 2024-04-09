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

#### Requirements for this Superpower

1. Create a GitHub App inside your organization or repository.
2. That GitHub App needs to have the following permissions:
    - Read contents of repository.
    - Read members of the organization.
3. Use the [actions/create-github-app-token@v1](https://github.com/actions/create-github-app-token) before use the GATE with Superpowers.
