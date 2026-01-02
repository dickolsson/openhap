# Commit and Push Changes

Analyze the current uncommitted changes and create well-organized commits
following the project's Conventional Commits standard (see main Copilot
instructions for details).

## Workflow

1. Run `make check` to verify code quality
   - If issues are minor (style/formatting), fix them with `make tidy-fix` and
     proceed
   - If issues are significant, stop and inform the user
2. Run `git status` and `git diff` to review all changes
3. Group related changes into logical commits
4. Create commits using Conventional Commits format (refer to main instructions
   for types, scopes, and examples)
5. Stage and commit each group separately
6. Push all commits to the remote

## Fallback

If unable to run commands in the terminal, provide all commands needed to commit
and push the changes.
