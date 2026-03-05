#!/usr/bin/env bash
#
# verify-commits.sh — Verify SVM has all relevant Agave commits.
#
# Given two SVM refs (base and head), this script extracts the Agave rev pins
# from each, then lists all Agave commits in that pin range that touch SVM-
# owned paths. Each commit is classified — by matching commit subjects — as
# cherry-picked, skippable (dep bumps, cargo-only), or unaccounted.
#
# The two key ranges:
#   Agave:  BASE_PIN..AGAVE_REF  (derived from SVM `rev` pins)
#   SVM:    BASE_REF..HEAD_REF  (the SVM branch being audited)
#
# Usage:
#   verify-commits.sh [OPTIONS]
#
# Options:
#   --agave-repo PATH   Path to local Agave checkout (default: ~/work/agave).
#   --agave-ref REF     Agave ref for end of range. Overrides the rev pin
#                        extracted from Cargo.toml at HEAD_REF.
#   --base-ref REF      SVM ref whose rev pin gives the start of the Agave
#                        range (default: merge-base of HEAD and master).
#   --head-ref REF      SVM ref whose rev pin gives the end of the Agave
#                        range (default: HEAD).
#   --diff              Show files touched by unaccounted commits.
#   --help              Show this help.
#
# Exit codes:
#   0  All commits accounted for
#   1  Unaccounted commits found (review output)
#   2  Usage / configuration error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

AGAVE_REPO="${AGAVE_REPO:-$HOME/work/agave}"
AGAVE_REF=""
BASE_REF=""
HEAD_REF="HEAD"
SHOW_DIFF=false

usage() {
    sed -n '/^# Usage:/,/^[^#]/{/^[^#]/q; s/^# \?//p;}' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agave-repo)   AGAVE_REPO="$2"; shift 2 ;;
        --agave-ref)    AGAVE_REF="$2";  shift 2 ;;
        --base-ref)     BASE_REF="$2";   shift 2 ;;
        --head-ref)     HEAD_REF="$2";   shift 2 ;;
        --diff)         SHOW_DIFF=true;  shift ;;
        --help|-h)      usage ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ -d "$AGAVE_REPO/.git" ]] || die "Agave repo not found at $AGAVE_REPO"
git rev-parse --git-dir >/dev/null 2>&1 || die "Not inside an SVM git repository"

# Resolve the Agave ref (end of range).
if [[ -z "$AGAVE_REF" ]]; then
    AGAVE_REF=$(get_agave_pin "$HEAD_REF")
    [[ -n "$AGAVE_REF" ]] || die "Could not extract Agave rev pin from Cargo.toml at $HEAD_REF. Use --agave-ref."
fi

git -C "$AGAVE_REPO" cat-file -t "$AGAVE_REF" >/dev/null 2>&1 \
    || die "Agave repo does not contain commit $AGAVE_REF — try: git -C $AGAVE_REPO fetch"

# Resolve base ref and base pin (start of Agave range).
if [[ -z "$BASE_REF" ]]; then
    BASE_REF=$(git merge-base "$HEAD_REF" master 2>/dev/null) \
        || die "Could not determine merge-base. Use --base-ref."
fi

BASE_PIN=$(get_agave_pin "$BASE_REF")
[[ -n "$BASE_PIN" ]] || die "Could not extract Agave rev pin from Cargo.toml at $BASE_REF. Use --base-ref."

git -C "$AGAVE_REPO" cat-file -t "$BASE_PIN" >/dev/null 2>&1 \
    || die "Agave repo does not contain commit $BASE_PIN — try: git -C $AGAVE_REPO fetch"

echo "$(bold 'SVM <-> Agave Commit Audit')"
echo ""
echo "  SVM head ref:   $HEAD_REF"
echo "  SVM base ref:   $(echo "$BASE_REF" | head -c 12)"
echo "  Agave ref:      $AGAVE_REF"
echo "  Agave base pin: $BASE_PIN"
echo "  Agave repo:     $AGAVE_REPO"
echo ""

EXIT_CODE=0

echo "SVM commit range:   $(echo "$BASE_REF" | head -c 12)..$HEAD_REF"
echo "Agave commit range: $BASE_PIN..$AGAVE_REF"
echo ""

# Collect commit subjects from the SVM branch. These are matched against Agave
# commits to identify cherry-picks (subjects are preserved by the import script).
declare -A svm_subjects=()
while IFS= read -r subj; do
    svm_subjects["$subj"]=1
done < <(git log --format="%s" "$BASE_REF..$HEAD_REF")

# Build Agave path args for git log (using agave-side paths).
path_args=""
for p in "${SVM_PATHS[@]}"; do
    path_args="$path_args $(agave_path_for "$p")/"
done

cherry_count=0
skip_dep_count=0
missing_count=0
declare -A cherry_picked_subjects=()

echo "  $(bold 'Legend:')"
echo "    [cherry-picked]  [dep-bump/cargo-only]  [?missing]"
echo ""

# Read all agave commits into an array to avoid subshell variable scoping.
agave_lines=()
while IFS= read -r line; do
    agave_lines+=("$line")
done < <(git -C "$AGAVE_REPO" log --format="%H %s" "$BASE_PIN..$AGAVE_REF" -- $path_args)

for line in "${agave_lines[@]}"; do
    [[ -n "$line" ]] || continue
    sha="${line%% *}"
    subject="${line#* }"

    if [[ -n "${svm_subjects["$subject"]+x}" ]]; then
        # Subject matches a commit in the SVM branch.
        printf "    %s  %s\n" "$(green 'OK')" "$subject"
        cherry_picked_subjects["$subject"]=1
        cherry_count=$((cherry_count + 1))
    elif echo "$subject" | grep -qP '^build\(deps\):|^chore\(deps\):'; then
        # Dependency bump — handled by workspace Cargo.toml, safe to skip.
        printf "    %s  %s\n" "$(dim '--')" "$subject"
        skip_dep_count=$((skip_dep_count + 1))
    else
        # Check if the commit only touches Cargo.toml/lock in SVM paths
        # (no source changes) — these are cargo-only, safe to skip.
        touched_src=$(git -C "$AGAVE_REPO" diff-tree --no-commit-id --name-only -r "$sha" -- $path_args \
            | grep -v 'Cargo\.\(toml\|lock\)$' | head -1 || echo "")

        if [[ -z "$touched_src" ]]; then
            printf "    %s  %s\n" "$(dim '--')" "$subject"
            skip_dep_count=$((skip_dep_count + 1))
        else
            # Touches SVM source code but not in SVM — flag it.
            printf "    %s  %s\n" "$(red '??')" "$subject"

            if $SHOW_DIFF; then
                echo "        Files in SVM paths:"
                git -C "$AGAVE_REPO" diff-tree --no-commit-id --name-only -r "$sha" -- $path_args \
                    | sed 's/^/          /'
                echo ""
            fi

            missing_count=$((missing_count + 1))
        fi
    fi
done

echo ""
echo "  $(bold 'Summary:')"
printf "    Cherry-picked:         %d\n" "$cherry_count"
printf "    Skipped (dep/cargo):   %d\n" "$skip_dep_count"
if [[ $missing_count -gt 0 ]]; then
    printf "    $(red 'Unaccounted:           %d')\n" "$missing_count"
    EXIT_CODE=1
else
    printf "    Unaccounted:           %d\n" "$missing_count"
fi

# Show SVM-only commits that don't correspond to any Agave cherry-pick.
echo ""
echo "  $(bold 'SVM-only maintenance commits:')"
has_maintenance=false
while IFS= read -r subject; do
    [[ -n "$subject" ]] || continue
    if [[ -z "${cherry_picked_subjects["$subject"]+x}" ]]; then
        printf "    %s  %s\n" "M " "$subject"
        has_maintenance=true
    fi
done < <(git log --format="%s" "$BASE_REF..$HEAD_REF")

if ! $has_maintenance; then
    echo "    (none)"
fi

echo ""
echo "$(bold '=== Result ===')"
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "$(green 'PASS') — all Agave commits accounted for in $BASE_PIN..$AGAVE_REF"
else
    echo "$(yellow 'UNACCOUNTED COMMITS') — review output above"
    echo ""
    echo "Use --diff to see files touched by unaccounted commits."
fi

exit $EXIT_CODE
