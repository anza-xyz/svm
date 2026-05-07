#!/usr/bin/env bash
#
# verify-tree.sh — Compare SVM crate directories against their upstreams.
#
# For each SVM-owned crate path, compare git tree hashes (and file-level
# content for mismatches) between the upstream at the target ref and SVM at
# HEAD. The path is dispatched to the right upstream via the UPSTREAM map in
# utils.sh. Used to verify the end-state is correct after a sync or rebase.
#
# Usage:
#   verify-tree.sh [OPTIONS]
#
# Options:
#   --agave-repo PATH   Path to local Agave checkout (default: ~/work/agave)
#   --agave-ref REF     Agave commit to compare against (default: extracted
#                        from agave-feature-set rev pin in Cargo.toml at HEAD_REF)
#   --sbpf-repo PATH    Path to local sbpf checkout (default: ~/work/sbpf)
#   --sbpf-ref REF      sbpf commit to compare against (default: extracted
#                        from solana-sbpf rev pin in Cargo.toml at HEAD_REF)
#   --upstream NAME     Only verify paths from one upstream: agave | sbpf
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
SBPF_REPO="${SBPF_REPO:-$HOME/work/sbpf}"
SBPF_REF=""
UPSTREAM_FILTER=""
HEAD_REF="HEAD"
SHOW_DIFF=false

# Track which per-upstream flags were explicitly passed, so we can reject
# combinations like `--upstream agave --sbpf-ref X`.
declare -A FLAG_SET=()

usage() {
    sed -n '/^# Usage:/,/^[^#]/{/^[^#]/q; s/^# \?//p;}' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agave-repo)   AGAVE_REPO="$2"; FLAG_SET[--agave-repo]=1; shift 2 ;;
        --agave-ref)    AGAVE_REF="$2";  FLAG_SET[--agave-ref]=1;  shift 2 ;;
        --sbpf-repo)    SBPF_REPO="$2";  FLAG_SET[--sbpf-repo]=1;  shift 2 ;;
        --sbpf-ref)     SBPF_REF="$2";   FLAG_SET[--sbpf-ref]=1;   shift 2 ;;
        --upstream)     UPSTREAM_FILTER="$2"; shift 2 ;;
        --head-ref)     HEAD_REF="$2";   shift 2 ;;
        --diff)         SHOW_DIFF=true;  shift ;;
        --help|-h)      usage ;;
        *) die "Unknown option: $1" ;;
    esac
done

case "$UPSTREAM_FILTER" in
    ""|agave|sbpf) ;;
    *) die "Invalid --upstream value: $UPSTREAM_FILTER (expected: agave | sbpf)" ;;
esac

# Reject flags that target the upstream the user filtered out.
if [[ "$UPSTREAM_FILTER" == "agave" ]]; then
    for f in --sbpf-repo --sbpf-ref; do
        [[ -n "${FLAG_SET[$f]:-}" ]] && die "$f is not valid with --upstream agave"
    done
elif [[ "$UPSTREAM_FILTER" == "sbpf" ]]; then
    for f in --agave-repo --agave-ref; do
        [[ -n "${FLAG_SET[$f]:-}" ]] && die "$f is not valid with --upstream sbpf"
    done
fi

git rev-parse --git-dir >/dev/null 2>&1 || die "Not inside an SVM git repository"

want_upstream() {
    [[ -z "$UPSTREAM_FILTER" || "$UPSTREAM_FILTER" == "$1" ]]
}

# Resolve and validate refs/repos for each upstream we plan to check.
declare -A REPO=()
declare -A REF=()

if want_upstream agave; then
    [[ -d "$AGAVE_REPO/.git" ]] || die "Agave repo not found at $AGAVE_REPO"
    if [[ -z "$AGAVE_REF" ]]; then
        AGAVE_REF=$(get_pin "agave-feature-set" "$HEAD_REF")
        [[ -n "$AGAVE_REF" ]] || die "Could not extract Agave rev pin from Cargo.toml at $HEAD_REF. Use --agave-ref."
    fi
    git -C "$AGAVE_REPO" cat-file -t "$AGAVE_REF" >/dev/null 2>&1 \
        || die "Agave repo does not contain commit $AGAVE_REF — try: git -C $AGAVE_REPO fetch"
    REPO[agave]="$AGAVE_REPO"
    REF[agave]="$AGAVE_REF"
fi

if want_upstream sbpf; then
    [[ -d "$SBPF_REPO/.git" ]] || die "sbpf repo not found at $SBPF_REPO (use --sbpf-repo, or --upstream agave to skip)"
    if [[ -z "$SBPF_REF" ]]; then
        SBPF_REF=$(get_pin "solana-sbpf" "$HEAD_REF")
        [[ -n "$SBPF_REF" ]] || die "Could not extract sbpf rev pin from Cargo.toml at $HEAD_REF. Use --sbpf-ref."
    fi
    git -C "$SBPF_REPO" cat-file -t "$SBPF_REF" >/dev/null 2>&1 \
        || die "sbpf repo does not contain commit $SBPF_REF — try: git -C $SBPF_REPO fetch"
    REPO[sbpf]="$SBPF_REPO"
    REF[sbpf]="$SBPF_REF"
fi

echo "$(bold 'SVM <-> Upstream Tree Comparison')"
echo ""
echo "  SVM head ref:   $HEAD_REF"
if want_upstream agave; then
    echo "  Agave ref:      $AGAVE_REF   (repo: $AGAVE_REPO)"
fi
if want_upstream sbpf; then
    echo "  sbpf ref:       $SBPF_REF   (repo: $SBPF_REPO)"
fi
echo ""

EXIT_CODE=0

match_count=0
mismatch_count=0
mismatch_svm_paths=()
mismatch_up_paths=()
mismatch_upstreams=()

for svm_pkg_path in "${SVM_PATHS[@]}"; do
    up="${UPSTREAM[$svm_pkg_path]:-}"
    [[ -n "$up" ]] || die "Path $svm_pkg_path has no upstream tag in utils.sh"

    if [[ -n "$UPSTREAM_FILTER" && "$up" != "$UPSTREAM_FILTER" ]]; then
        continue
    fi

    up_repo="${REPO[$up]}"
    up_ref="${REF[$up]}"
    up_pkg_path=$(upstream_path_for "$svm_pkg_path")

    up_hash=$(git -C "$up_repo" rev-parse "$up_ref:$up_pkg_path" 2>/dev/null || echo "MISSING")
    svm_hash=$(git rev-parse "$HEAD_REF:$svm_pkg_path" 2>/dev/null || echo "MISSING")

    label="$svm_pkg_path"
    [[ "$up_pkg_path" != "$svm_pkg_path" ]] && label="$svm_pkg_path ($up: $up_pkg_path)"

    if [[ "$up_hash" == "$svm_hash" ]]; then
        printf "  %s %-45s %s\n" "$(green 'OK')" "$label/" "${up_hash:0:12}"
        match_count=$((match_count + 1))
    else
        printf "  %s %-45s %s\n" "$(red '!!')" "$label/" "$up=${up_hash:0:12} svm=${svm_hash:0:12}"
        mismatch_count=$((mismatch_count + 1))
        mismatch_svm_paths+=("$svm_pkg_path")
        mismatch_up_paths+=("$up_pkg_path")
        mismatch_upstreams+=("$up")
    fi
done

checked=$((match_count + mismatch_count))
echo ""
echo "  Matched: $match_count / $checked checked"
if [[ $mismatch_count -gt 0 ]]; then
    echo "  $(red "Mismatched: $mismatch_count")"
fi

# Drill into mismatches: for each mismatched crate, list files relative to
# the crate root and classify as upstream-only, svm-only, or modified.
if [[ ${#mismatch_svm_paths[@]} -gt 0 ]]; then
    echo ""
    echo "$(bold '--- File-level breakdown of mismatches ---')"

    for i in "${!mismatch_svm_paths[@]}"; do
        svm_pkg_path="${mismatch_svm_paths[$i]}"
        up_pkg_path="${mismatch_up_paths[$i]}"
        up="${mismatch_upstreams[$i]}"
        up_repo="${REPO[$up]}"
        up_ref="${REF[$up]}"

        echo ""
        if [[ "$up_pkg_path" != "$svm_pkg_path" ]]; then
            echo "  $(bold "$svm_pkg_path/") ($up: $up_pkg_path/)"
        else
            echo "  $(bold "$svm_pkg_path/") ($up)"
        fi

        # List files relative to crate root (strip the crate prefix) so we
        # can compare across repos even when directory names differ.
        up_files=$(git -C "$up_repo" ls-tree -r --name-only "$up_ref" -- "$up_pkg_path/" 2>/dev/null \
            | sed "s|^$up_pkg_path/||" | sort)
        svm_files=$(git ls-tree -r --name-only "$HEAD_REF" -- "$svm_pkg_path/" 2>/dev/null \
            | sed "s|^$svm_pkg_path/||" | sort)

        # Files only in upstream
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            printf "    %s  %s\n" "$(red "+$up")" "$f"
        done < <(comm -23 <(echo "$up_files") <(echo "$svm_files"))

        # Files only in SVM
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            printf "    %s    %s\n" "$(yellow '+svm')" "$f"
        done < <(comm -13 <(echo "$up_files") <(echo "$svm_files"))

        # Shared files with content differences
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            up_blob=$(git -C "$up_repo" rev-parse "$up_ref:$up_pkg_path/$f" 2>/dev/null || echo "")
            svm_blob=$(git rev-parse "$HEAD_REF:$svm_pkg_path/$f" 2>/dev/null || echo "")
            if [[ "$up_blob" != "$svm_blob" ]]; then
                printf "    %s %s\n" "$(yellow '~mod')" "$f"

                if $SHOW_DIFF; then
                    diff --unified=3 \
                        --label "$up:$up_pkg_path/$f" \
                        --label "svm:$svm_pkg_path/$f" \
                        <(git -C "$up_repo" show "$up_ref:$up_pkg_path/$f" 2>/dev/null) \
                        <(git show "$HEAD_REF:$svm_pkg_path/$f" 2>/dev/null) \
                        | sed 's/^/        /' || true
                    echo ""
                fi
            fi
        done < <(comm -12 <(echo "$up_files") <(echo "$svm_files"))
    done

    EXIT_CODE=1
fi

echo ""
echo "$(bold '=== Result ===')"
if [[ $EXIT_CODE -eq 0 ]]; then
    parts=()
    want_upstream agave && parts+=("agave@$AGAVE_REF")
    want_upstream sbpf  && parts+=("sbpf@$SBPF_REF")
    echo "$(green 'PASS') — SVM tree matches ${parts[*]}"
else
    echo "$(yellow 'DIVERGENCES FOUND') — review output above"
    echo ""
    echo "Use --diff for file-level unified diffs."
fi

exit $EXIT_CODE
