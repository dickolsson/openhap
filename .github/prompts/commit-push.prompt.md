# Commit and Push Changes

Analyze the current uncommitted changes and create well-organized commits.

## Instructions

1. Run `make check` to verify code quality
   - If issues are minor (style/formatting), fix them and proceed
   - If issues are significant, stop and inform the user
2. Run `git status` and `git diff` to review all changes
3. Group related changes into logical commits
3. Create commits using **Conventional Commits** format:
   - `feat:` new feature
   - `fix:` bug fix
   - `docs:` documentation only
   - `style:` formatting, no code change
   - `refactor:` code change without feat/fix
   - `test:` adding/updating tests
   - `chore:` maintenance tasks
4. Use scope when helpful: `feat(mqtt): add reconnect logic`
5. Keep subject line under 72 characters
6. Stage and commit each group separately
7. Push all commits to the remote

## Example

```
feat(config): add validation for port ranges
fix(session): handle disconnect during handshake
docs: update README with new options
```

## Fallback

If unable to run commands in the terminal,
provide all commands needed to commit and push the changes.
