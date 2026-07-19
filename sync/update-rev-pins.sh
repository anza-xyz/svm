#!/usr/bin/env bash
#
# update-rev-pins.sh — Update upstream rev pins in the workspace Cargo.toml.
#
# The SVM workspace pins three upstreams via git deps:
#   * agave — packages prefixed `agave-` or `solana-` (excluding solana-sbpf
#             and solana-svm-transaction)
#   * sbpf  — the `solana-sbpf` package
#   * sdk   — the `solana-svm-transaction` package (moved out of agave)
#
# Usage:
#   sync/update-rev-pins.sh agave <new-rev>
#   sync/update-rev-pins.sh sbpf  <new-rev>
#   sync/update-rev-pins.sh sdk   <new-rev>
#
# Useful during rebase of the `svm` branch after syncing `master`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if [[ $# -ne 2 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: sync/update-rev-pins.sh <upstream> <new-rev>"
    echo "  upstream: agave | sbpf | sdk"
    exit 2
fi

UPSTREAM_NAME="$1"
NEW_REV="$2"
MANIFEST="Cargo.toml"

[[ -f "$MANIFEST" ]] || die "$MANIFEST not found"

# Define which package-name prefixes belong to each upstream.
# The regex is applied to the start of each line in Cargo.toml. The agave
# pattern uses PCRE negative lookaheads to exclude solana-sbpf and
# solana-svm-transaction (which belong to other upstreams), so the match
# below requires `grep -P` (GNU grep on Linux; BSD grep on macOS does not
# support -P and will silently match nothing).
case "$UPSTREAM_NAME" in
    agave) PREFIX_REGEX='^[[:space:]]*(agave-|solana-(?!sbpf[[:space:]]*=)(?!svm-transaction[[:space:]]*=))' ;;
    sbpf)  PREFIX_REGEX='^[[:space:]]*solana-sbpf[[:space:]]*=' ;;
    sdk)   PREFIX_REGEX='^[[:space:]]*solana-svm-transaction[[:space:]]*=' ;;
    *)     die "Unknown upstream: $UPSTREAM_NAME (expected: agave | sbpf | sdk)" ;;
esac

REV_REGEX='rev[[:space:]]*=[[:space:]]*"[^"]+"'

count=0
unchanged=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
    if printf '%s' "$line" | grep -qP "$PREFIX_REGEX" \
        && printf '%s' "$line" | grep -qP "$REV_REGEX"; then
        new_line=$(printf '%s' "$line" \
            | sed -E "s/(rev[[:space:]]*=[[:space:]]*)\"[^\"]+\"/\1\"$NEW_REV\"/")
        if [[ "$new_line" != "$line" ]]; then
            count=$((count + 1))
            line="$new_line"
        else
            unchanged=$((unchanged + 1))
        fi
    fi
    printf '%s\n' "$line" >> "$tmp"
done < "$MANIFEST"

mv "$tmp" "$MANIFEST"
trap - EXIT

if [[ $count -eq 0 ]]; then
    if [[ $unchanged -gt 0 ]]; then
        echo "Already at $NEW_REV — $unchanged $UPSTREAM_NAME pin(s) unchanged."
    else
        echo "WARNING: no $UPSTREAM_NAME rev pins found in $MANIFEST" >&2
    fi
    exit 0
fi

echo "Updated $count $UPSTREAM_NAME rev pin(s) to $NEW_REV"
