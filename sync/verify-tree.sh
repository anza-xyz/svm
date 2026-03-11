#!/usr/bin/env bash
#
# verify-tree.sh — Compare SVM crate directories against Agave.
#
# For each SVM-owned crate path that also exists in Agave, compare git tree
# hashes (and file-level content for mismatches) between Agave at the target
# ref and SVM at HEAD. This verifies the end-state is correct.
#
# Usage:
#   verify-tree.sh [OPTIONS]
#
# Options:
#   --agave-repo PATH   Path to local Agave checkout (default: ~/work/agave)
#   --agave-ref REF     Agave commit to compare against (default: extracted
#                        from rev pin in Cargo.toml at HEAD_REF)
#   --head-ref REF      SVM ref to verify (default: HEAD)
#   --diff              Show unified diffs for mismatched files
#   --help              Show this help
#
# Exit codes:
#   0  Everything matches
#   1  Divergences found (review output)
#   2  Usage / configuration error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

AGAVE_REPO="${AGAVE_REPO:-$HOME/work/agave}"
AGAVE_REF=""
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
        --head-ref)     HEAD_REF="$2";   shift 2 ;;
        --diff)         SHOW_DIFF=true;  shift ;;
        --help|-h)      usage ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ -d "$AGAVE_REPO/.git" ]] || die "Agave repo not found at $AGAVE_REPO"
git rev-parse --git-dir >/dev/null 2>&1 || die "Not inside an SVM git repository"

# Resolve the Agave ref to compare against.
if [[ -z "$AGAVE_REF" ]]; then
    AGAVE_REF=$(get_agave_pin "$HEAD_REF")
    [[ -n "$AGAVE_REF" ]] || die "Could not extract Agave rev pin from Cargo.toml at $HEAD_REF. Use --agave-ref."
fi

git -C "$AGAVE_REPO" cat-file -t "$AGAVE_REF" >/dev/null 2>&1 \
    || die "Agave repo does not contain commit $AGAVE_REF — try: git -C $AGAVE_REPO fetch"

echo "$(bold 'SVM <-> Agave Tree Comparison')"
echo ""
echo "  SVM head ref:   $HEAD_REF"
echo "  Agave ref:      $AGAVE_REF"
echo "  Agave repo:     $AGAVE_REPO"
echo ""

EXIT_CODE=0

echo "Comparing SVM-owned crate directories between:"
echo "  SVM   @ $HEAD_REF"
echo "  Agave @ $AGAVE_REF"
echo ""

match_count=0
mismatch_count=0
mismatch_svm_paths=()
mismatch_agave_paths=()

for svm_pkg_path in "${SVM_PATHS[@]}"; do
    agv_pkg_path=$(agave_path_for "$svm_pkg_path")

    agv_hash=$(git -C "$AGAVE_REPO" rev-parse "$AGAVE_REF:$agv_pkg_path" 2>/dev/null || echo "MISSING")
    svm_hash=$(git rev-parse "$HEAD_REF:$svm_pkg_path" 2>/dev/null || echo "MISSING")

    label="$svm_pkg_path"
    [[ "$agv_pkg_path" != "$svm_pkg_path" ]] && label="$svm_pkg_path (agave: $agv_pkg_path)"

    if [[ "$agv_hash" == "$svm_hash" ]]; then
        printf "  %s %-35s %s\n" "$(green 'OK')" "$label/" "${agv_hash:0:12}"
        match_count=$((match_count + 1))
    else
        printf "  %s %-35s %s\n" "$(red '!!')" "$label/" "agave=${agv_hash:0:12} svm=${svm_hash:0:12}"
        mismatch_count=$((mismatch_count + 1))
        mismatch_svm_paths+=("$svm_pkg_path")
        mismatch_agave_paths+=("$agv_pkg_path")
    fi
done

checked=$((match_count + mismatch_count))
echo ""
echo "  Matched: $match_count / $checked checked"
if [[ $mismatch_count -gt 0 ]]; then
    echo "  $(red "Mismatched: $mismatch_count")"
fi

# Drill into mismatches: for each mismatched crate, list files relative to
# the crate root and classify as agave-only, svm-only, or modified.
if [[ ${#mismatch_svm_paths[@]} -gt 0 ]]; then
    echo ""
    echo "$(bold '--- File-level breakdown of mismatches ---')"

    for i in "${!mismatch_svm_paths[@]}"; do
        svm_pkg_path="${mismatch_svm_paths[$i]}"
        agv_pkg_path="${mismatch_agave_paths[$i]}"

        echo ""
        if [[ "$agv_pkg_path" != "$svm_pkg_path" ]]; then
            echo "  $(bold "$svm_pkg_path/") (agave: $agv_pkg_path/)"
        else
            echo "  $(bold "$svm_pkg_path/")"
        fi

        # List files relative to crate root (strip the crate prefix) so we
        # can compare across repos even when directory names differ.
        agv_files=$(git -C "$AGAVE_REPO" ls-tree -r --name-only "$AGAVE_REF" -- "$agv_pkg_path/" 2>/dev/null \
            | sed "s|^$agv_pkg_path/||" | sort)
        svm_files=$(git ls-tree -r --name-only "$HEAD_REF" -- "$svm_pkg_path/" 2>/dev/null \
            | sed "s|^$svm_pkg_path/||" | sort)

        # Files only in Agave
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            printf "    %s  %s\n" "$(red '+agave')" "$f"
        done < <(comm -23 <(echo "$agv_files") <(echo "$svm_files"))

        # Files only in SVM
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            printf "    %s    %s\n" "$(yellow '+svm')" "$f"
        done < <(comm -13 <(echo "$agv_files") <(echo "$svm_files"))

        # Shared files with content differences
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            agv_blob=$(git -C "$AGAVE_REPO" rev-parse "$AGAVE_REF:$agv_pkg_path/$f" 2>/dev/null || echo "")
            svm_blob=$(git rev-parse "$HEAD_REF:$svm_pkg_path/$f" 2>/dev/null || echo "")
            if [[ "$agv_blob" != "$svm_blob" ]]; then
                printf "    %s %s\n" "$(yellow '~mod')" "$f"

                if $SHOW_DIFF; then
                    diff --unified=3 \
                        --label "agave:$agv_pkg_path/$f" \
                        --label "svm:$svm_pkg_path/$f" \
                        <(git -C "$AGAVE_REPO" show "$AGAVE_REF:$agv_pkg_path/$f" 2>/dev/null) \
                        <(git show "$HEAD_REF:$svm_pkg_path/$f" 2>/dev/null) \
                        | sed 's/^/        /' || true
                    echo ""
                fi
            fi
        done < <(comm -12 <(echo "$agv_files") <(echo "$svm_files"))
    done

    EXIT_CODE=1
fi

echo ""
echo "$(bold '=== Result ===')"
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "$(green 'PASS') — SVM tree matches Agave at $AGAVE_REF"
else
    echo "$(yellow 'DIVERGENCES FOUND') — review output above"
    echo ""
    echo "Use --diff for file-level unified diffs."
fi

exit $EXIT_CODE
