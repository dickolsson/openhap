---
name: commit-push
description:
  Group uncommitted changes into logical Conventional Commits and push. Use when
  asked to commit, commit and push, or clean up the working tree into commits.
  Runs make check first.
---

# Commit and Push Changes

## Objective

Analyze the current uncommitted changes and create well-organized commits
following the project's Conventional Commits standard (see the root CLAUDE.md
for types, scopes, and examples).

## Workflow

1. Run `make check` to verify code quality
   - If issues are minor (style/formatting), fix them with `make tidy-fix` and
     proceed
   - If issues are significant, stop and inform the user
2. Run `git status` and `git diff` to review all changes
3. Group related changes into logical commits
4. Create commits using Conventional Commits format (refer to CLAUDE.md for
   types, scopes, and examples)
5. Stage and commit each group separately
6. Push all commits to the remote
