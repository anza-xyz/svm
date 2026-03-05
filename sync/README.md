# Sync Tools

Requires a local Agave checkout (default: `~/work/agave`).

## Tree comparison (`verify-tree.sh`)

```bash
# Compare SVM HEAD against the rev pin in Cargo.toml.
sync/verify-tree.sh

# Compare against an explicit Agave ref (e.g., for sync PRs to master).
sync/verify-tree.sh --agave-ref a48940a24d

# Show unified diffs for mismatched files.
sync/verify-tree.sh --agave-ref a48940a24d --diff
```

## Commit audit (`verify-commits.sh`)

```bash
# Audit commits between merge-base and HEAD.
sync/verify-commits.sh

# Audit from the initial SVM commit.
sync/verify-commits.sh --base-ref b2ffcb08

# Show files touched by unaccounted commits.
sync/verify-commits.sh --diff
```
