# SVM ↔ Upstream Sync Workflow

## Branch Structure

🟢 **`master`** — Imported upstream commits only, in chronological order.
Sourced from three upstreams:

- `anza-xyz/agave` — filtered to SVM-owned crate paths, with path renames
  applied (e.g. `svm-callback/` in agave becomes `callback/` in SVM).
- `anza-xyz/sbpf` — imported as a subtree merge into `sbpf/`.
- `anza-xyz/solana-sdk` — filtered to `svm-transaction`, renamed to
  `transaction/` in SVM (moved out of agave).

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

The workspace `Cargo.toml` carries three distinct rev pin sets, one per
upstream:

- **Agave-prefixed packages** (`agave-*`, `solana-*` excluding `solana-sbpf`
  and `solana-svm-transaction`) pin to a commit in `anza-xyz/agave`.
- **`solana-sbpf`** pins to a commit in `anza-xyz/sbpf`.
- **`solana-svm-transaction`** pins to a commit in `anza-xyz/solana-sdk`.

The three sets advance independently — sync PRs target one upstream at a time,
so a rebase typically bumps one set and leaves the others alone.

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
sync/verify-tree.sh --upstream sdk     # for solana-sdk sync PRs
```

Merge the new commits to `master`.

### 🟣 **Step 2:** Rebase the `svm` branch.

Rebase the `svm` branch onto the latest `master`. Edit the anchor commit to
update `rev` pins for whichever upstream(s) advanced, then regenerate
`Cargo.lock`.


The upstreams use different import shapes on `master`, so identifying the new
tip pin differs by upstream:

- **Agave** — imports are linear commits that preserve the upstream subject
  and author. The most recent import sits at the tip of `master`'s
  first-parent chain (skipping subtree merges). Resolve the upstream SHA by
  re-matching the preserved subject in the local agave clone.
- **sbpf** — imports are subtree merges with subject
  `Merge anza-xyz/sbpf into sbpf/ subdirectory`. The upstream SHA is the
  second parent of the merge commit.
- **sdk** — same linear, subject-preserving shape as agave. Because agave and
  sdk imports look alike on `master`, disambiguate by which clone the subject
  resolves in: an sdk import resolves in the solana-sdk clone, not agave.

```bash
# Agave: walk master's first-parent chain, skipping merges, to find the
# most recent import; then look it up by subject in the agave clone.
AGAVE_REV_COMMIT=$(git log master --first-parent --no-merges --format="%H" -1)
AGAVE_REV=$(git -C ~/work/agave log --format="%H" --all \
    --grep="$(git log -1 --format='%s' "$AGAVE_REV_COMMIT")" -1)
sync/update-rev-pins.sh agave "$AGAVE_REV"

# sbpf: the upstream SHA is the second parent of the most recent subtree
# merge commit.
SBPF_MERGE=$(git log master --grep="^Merge anza-xyz/sbpf into sbpf" -1 --format="%H")
SBPF_REV=$(git rev-parse "$SBPF_MERGE^2")
sync/update-rev-pins.sh sbpf "$SBPF_REV"

# sdk: locate the most recent import that touches transaction/ and resolve
# its preserved subject in the solana-sdk clone.
SDK_REV_COMMIT=$(git log master --first-parent --no-merges --format="%H" -1 -- transaction/)
SDK_REV=$(git -C ~/work/solana-sdk log --format="%H" --all \
    --grep="$(git log -1 --format='%s' "$SDK_REV_COMMIT")" -1)
sync/update-rev-pins.sh sdk "$SDK_REV"

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
