# SVM ↔ Agave Sync Workflow

## Branch Structure

🟢 **`master`** — Agave commits only, in chronological order. Filtered to
SVM-owned crate paths, imported with original commit metadata intact.

🟣 **`svm`** — based on `master`, routinely rebased. Contains workspace setup
and infrastructure.

The commit stack on `svm` is ordered so that tooling is available early:

1. **Sync tooling** — `sync/` scripts (verify, update-rev-pins, etc.)
2. **Anchor commit** (`[DEVOPS]: svm-rev-pin`) — workspace scaffolding
3. **Infrastructure** — CI, xtask, repo metadata
4. **Tweak commits** — feature flags, dependency adjustments

The anchor commit adds the workspace scaffolding:

| File | Purpose |
|------|---------|
| `Cargo.toml` | Workspace manifest, `rev` pins, `[patch]` section, lints |
| `Cargo.lock` | Lockfile |
| `rust-toolchain.toml` | Toolchain version |
| `clippy.toml` | Clippy config |
| `rustfmt.toml` | Formatting config |

The `rev` pins point to the Agave commit that corresponds to the HEAD of
`master` (found by matching the commit subject against the Agave repo).

Sync tooling is placed before the anchor so that `sync/update-rev-pins.sh`
is available when editing the anchor during a rebase.

## Syncing Commits from Agave

### 🟢 **Step 1:** Open a "sync" PR to `master`.

The **devops import script** is used to add new commits starting from a base
ref.

> **Import script**: Devops-maintained script that imports Agave commits into
> the SVM repo, filters commits to SVM-owned paths, applies path renaming, and
> preserves original commit metadata.

PR is opened on SVM `master`, reviewers verify with:

```bash
sync/verify-tree.sh
```

Merge the new commits to `master`.

### 🟣 **Step 2:** Rebase the `svm` branch.

Rebase the `svm` branch onto the latest `master`, which includes the new Agave
commits.

Edit the anchor commit to update `rev` pins to the corresponding Agave
commit, then regenerate `Cargo.lock`:

```bash
# Find the Agave commit that corresponds to the SVM master HEAD.
# The SVM and Agave commit hashes differ (filtered tree), so match by subject.
AGAVE_REV=$(git -C ~/work/agave log --format="%H" --all \
    --grep="$(git log -1 --format='%s' master)" -1)

sync/update-rev-pins.sh "$AGAVE_REV"
cargo generate-lockfile
```

See [REBASE.md](../REBASE.md) for detailed step-by-step instructions.

Then continue the rebase and resolve any conflicts manually.

Force-push the changes up to the remote `svm` branch.

## Switching Over Development

1. Pause Agave SVM development (give heads-up for in-progress work)
2. Final sync PR to `master`
3. Final rebase of `svm` — update rev pins or switch to crates.io deps
4. Merge `svm` into `master`
5. Open for direct development; force-pushing stops
