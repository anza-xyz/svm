# Sync Tools

The SVM repo tracks two upstreams:

- **agave** — `anza-xyz/agave` (default local checkout: `~/work/agave`)
- **sbpf**  — `anza-xyz/sbpf`  (default local checkout: `~/work/sbpf`)

Override with `--agave-repo` / `--sbpf-repo` (or env vars `AGAVE_REPO` /
`SBPF_REPO`). All scripts accept `--upstream agave|sbpf` to limit work to a
single upstream — useful when reviewing a sync PR that targets only one.

## Tree comparison (`verify-tree.sh`)

```bash
# Compare SVM HEAD against both upstream rev pins from Cargo.toml.
sync/verify-tree.sh

# Compare against an explicit ref for one upstream (e.g., for sync PRs).
sync/verify-tree.sh --upstream agave --agave-ref <agave-commit>
sync/verify-tree.sh --upstream sbpf  --sbpf-ref  <sbpf-commit>

# Show unified diffs for mismatched files.
sync/verify-tree.sh --diff
```

## Commit audit (`verify-commits.sh`)

```bash
# Audit commits between merge-base and HEAD, both upstreams.
sync/verify-commits.sh

# Audit only one upstream.
sync/verify-commits.sh --upstream agave
sync/verify-commits.sh --upstream sbpf

# Audit from a specific base ref.
sync/verify-commits.sh --base-ref <svm-ref>

# Show files touched by unaccounted commits.
sync/verify-commits.sh --diff
```

## Rev pin updates (`update-rev-pins.sh`)

```bash
# Bump every Agave-side rev pin in workspace Cargo.toml.
sync/update-rev-pins.sh agave <new-agave-commit>

# Bump the solana-sbpf rev pin.
sync/update-rev-pins.sh sbpf <new-sbpf-commit>

# Regenerate the lockfile after either bump.
cargo generate-lockfile
```
