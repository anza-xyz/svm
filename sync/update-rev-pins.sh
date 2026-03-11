#!/usr/bin/env bash
#
# update-rev-pins.sh — Update all Agave rev pins in the workspace Cargo.toml.
#
# Usage:
#   sync/update-rev-pins.sh <new-rev>
#
# Replaces every `rev = "..."` value in the workspace Cargo.toml with the
# provided ref.
#
# Useful during rebase of the `svm` branch after syncing `master`.

set -euo pipefail

if [[ $# -ne 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: sync/update-rev-pins.sh <new-rev>"
    exit 2
fi

NEW_REV="$1"
MANIFEST="Cargo.toml"

[[ -f "$MANIFEST" ]] || { echo "ERROR: $MANIFEST not found" >&2; exit 2; }

OLD_REV=$(grep -m1 'rev = "' "$MANIFEST" | sed 's/.*rev = "\([^"]*\)".*/\1/')
if [[ -z "$OLD_REV" ]]; then
    echo "ERROR: no rev pins found in $MANIFEST" >&2
    exit 2
fi

if [[ "$OLD_REV" == "$NEW_REV" ]]; then
    echo "Already at $NEW_REV — nothing to do."
    exit 0
fi

count=$(grep -c "rev = \"$OLD_REV\"" "$MANIFEST")
sed -i "s/rev = \"$OLD_REV\"/rev = \"$NEW_REV\"/g" "$MANIFEST"

echo "Updated $count rev pins: $OLD_REV → $NEW_REV"
