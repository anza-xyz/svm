# SVM ↔ Upstream Sync Workflow

## Branch Structure

🟢 **`master`** — Imported upstream commits only, in chronological order.
Sourced from two upstreams:

- `anza-xyz/agave` — filtered to SVM-owned crate paths, with path renames
  applied (e.g. `svm-callback/` in agave becomes `callback/` in SVM).
- `anza-xyz/sbpf` — imported as a subtree merge into `sbpf/`.

Each commit preserves original commit metadata.

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

Sync tooling is placed before the anchor so that `sync/update-rev-pins.sh`
is available when editing the anchor during a rebase.

### `rev` pins

The workspace `Cargo.toml` carries two distinct rev pin sets, one per
upstream:

- **Agave-prefixed packages** (`agave-*`, `solana-*` excluding `solana-sbpf`)
  pin to a commit in `anza-xyz/agave`.
- **`solana-sbpf`** pins to a commit in `anza-xyz/sbpf`.

The two sets advance independently — sync PRs target one upstream at a time,
so a rebase typically bumps one set and leaves the other alone.

## Syncing Commits from an Upstream

### 🟢 **Step 1:** Open a "sync" PR to `master`.

Sync PRs target one upstream at a time. The **devops import script** is used
to add new commits starting from a base ref.

> **Import script**: Devops-maintained script that imports upstream commits
> into the SVM repo, filters commits to SVM-owned paths, applies path
> renaming (agave only), and preserves original commit metadata. Takes an
> upstream selector.

PR is opened on SVM `master`, reviewers verify with the matching
`--upstream` filter:

```bash
sync/verify-tree.sh --upstream agave   # for Agave sync PRs
sync/verify-tree.sh --upstream sbpf    # for sbpf sync PRs
```

Merge the new commits to `master`.

### 🟣 **Step 2:** Rebase the `svm` branch.

Rebase the `svm` branch onto the latest `master`. Edit the anchor commit to
update `rev` pins for whichever upstream(s) advanced, then regenerate
`Cargo.lock`.


```bash
# Find the most recent Agave import commit on master and resolve its
# upstream SHA.
AGAVE_REV_COMMIT=$(git log master --format="%H" --grep="<agave-marker>" -1)
AGAVE_REV=$(git -C ~/work/agave log --format="%H" --all \
    --grep="$(git log -1 --format='%s' "$AGAVE_REV_COMMIT")" -1)
sync/update-rev-pins.sh agave "$AGAVE_REV"

# Same for sbpf.
SBPF_REV_COMMIT=$(git log master --format="%H" --grep="<sbpf-marker>" -1)
SBPF_REV=$(git -C ~/work/sbpf log --format="%H" --all \
    --grep="$(git log -1 --format='%s' "$SBPF_REV_COMMIT")" -1)
sync/update-rev-pins.sh sbpf "$SBPF_REV"

cargo generate-lockfile
```

If only one upstream advanced, you only need to bump that one's pin.

Then continue the rebase and resolve any conflicts manually.

Force-push the changes up to the remote `svm` branch.

## Switching Over Development

1. Pause Agave SVM development (give heads-up for in-progress work)
2. Final sync PR to `master`
3. Final rebase of `svm` — update rev pins or switch to crates.io deps
4. Merge `svm` into `master`
5. Open for direct development; force-pushing stops
