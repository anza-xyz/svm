# Sync Tools

Requires a local Agave checkout (default: `~/work/agave`).

## Tree comparison (`verify-tree.sh`)

```bash
# Compare SVM HEAD against the rev pin in Cargo.toml.
sync/verify-tree.sh

# Compare against an explicit Agave ref (e.g., for sync PRs to master).
sync/verify-tree.sh --agave-ref <agave-commit>

# Show unified diffs for mismatched files.
sync/verify-tree.sh --agave-ref <agave-commit> --diff
```

## Commit audit (`verify-commits.sh`)

```bash
# Audit commits between merge-base and HEAD.
sync/verify-commits.sh

# Audit from a specific base ref.
sync/verify-commits.sh --base-ref <svm-ref>

# Show files touched by unaccounted commits.
sync/verify-commits.sh --diff
```
