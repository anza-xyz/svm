# SVM ↔ Agave Sync Workflow

## Branch Structure

🟢 **`master`** — Agave commits only, in chronological order. Filtered to
SVM-owned crate paths, imported with original commit metadata intact.

🟣 **`svm`** — based on `master`, routinely rebased. Contains workspace setup
and infrastructure.

The first commit on `svm` is the **anchor commit** (`[DEVOPS]: svm-rev-pin`).
It adds the workspace scaffolding:

| File | Purpose |
|------|---------|
| `Cargo.toml` | Workspace manifest, `rev` pins, `[patch]` section, lints |
| `Cargo.lock` | Lockfile |
| `rust-toolchain.toml` | Toolchain version |
| `clippy.toml` | Clippy config |
| `rustfmt.toml` | Formatting config |

The `rev` pins point to the HEAD of `master`.

After the anchor: **tweak commits** (feature flags, dependency adjustments)
and **infrastructure commits** (CI, scripts, sync tooling, repo metadata).

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

Edit the anchor commit to update `rev` pins to the new `master` HEAD using
the helper script, then regenerate `Cargo.lock`:

```bash
sync/update-rev-pins.sh $(git rev-parse master)
cargo generate-lockfile
```

Then continue the rebase and resolve any conflicts manually.

Force-push the changes up to the remote `svm` branch.

## Switching Over Development

1. Pause Agave SVM development (give heads-up for in-progress work)
2. Final sync PR to `master`
3. Final rebase of `svm` — update rev pins or switch to crates.io deps
4. Merge `svm` into `master`
5. Open for direct development; force-pushing stops
