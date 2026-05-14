#!/usr/bin/env bash
#
# verify-commits.sh — Verify SVM has all relevant upstream commits.
#
# Given two SVM refs (base and head), this script extracts the upstream rev
# pins from each, then for every upstream lists all commits in that pin range
# that touch SVM-owned paths. Each commit is classified — by matching commit
# subjects — as cherry-picked, skippable (dep bumps, cargo-only), or
# unaccounted.
#
# The audit runs once per upstream (agave, sbpf), unless --upstream filters
# to one. SVM-only maintenance commits are reported once, at the end.
#
# Usage:
#   verify-commits.sh [OPTIONS]
#
# Options:
#   --agave-repo PATH   Path to local Agave checkout (default: ~/work/agave).
#   --agave-ref REF     Agave ref for end of range. Overrides the rev pin
#                        extracted from Cargo.toml at HEAD_REF.
#   --sbpf-repo PATH    Path to local sbpf checkout (default: ~/work/sbpf).
#   --sbpf-ref REF      sbpf ref for end of range. Overrides the rev pin
#                        extracted from Cargo.toml at HEAD_REF.
#   --upstream NAME     Only audit one upstream: agave | sbpf
#   --base-ref REF      SVM ref whose rev pins give the start of each upstream
#                        range (default: merge-base of HEAD and master).
#   --head-ref REF      SVM ref whose rev pins give the end of each upstream
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
SBPF_REPO="${SBPF_REPO:-$HOME/work/sbpf}"
SBPF_REF=""
UPSTREAM_FILTER=""
BASE_REF=""
HEAD_REF="HEAD"
SHOW_DIFF=false

# Track which per-upstream flags were explicitly passed, so we can reject
# combinations like `--upstream agave --sbpf-ref X` (silently ignoring a
# user-supplied flag is a footgun).
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
        --base-ref)     BASE_REF="$2";   shift 2 ;;
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

# Resolve base ref (shared across upstreams).
if [[ -z "$BASE_REF" ]]; then
    BASE_REF=$(git merge-base "$HEAD_REF" master 2>/dev/null) \
        || die "Could not determine merge-base. Use --base-ref."
fi

# Collect commit subjects from the SVM branch once. Each upstream audit
# uses these to identify cherry-picks (subjects are preserved by the
# import script).
declare -A svm_subjects=()
while IFS= read -r subj; do
    svm_subjects["$subj"]=1
done < <(git log --format="%s" "$BASE_REF..$HEAD_REF")

# Track which subjects matched any upstream commit, so the end-of-run
# "SVM-only maintenance commits" section can list anything left over.
declare -A cherry_picked_subjects=()

EXIT_CODE=0
TOTAL_CHERRY=0
TOTAL_SKIP=0
TOTAL_MISSING=0

# audit_upstream <name> <repo> <base-pin> <head-pin>
#
# Walks the upstream's commit range and classifies each commit that touches
# this upstream's SVM-owned paths.
audit_upstream() {
    local name="$1" repo="$2" base_pin="$3" head_pin="$4"

    local path_args=""
    local p up_path
    for p in "${SVM_PATHS[@]}"; do
        [[ "${UPSTREAM[$p]:-}" == "$name" ]] || continue
        case "$name" in
            agave) up_path="${AGAVE_PATH[$p]:-$p}" ;;
            sbpf)  up_path="${SBPF_PATH[$p]:-$p}" ;;
        esac
        path_args="$path_args $up_path/"
    done

    if [[ -z "$path_args" ]]; then
        echo "  (no $name-owned paths in SVM_PATHS — skipping)"
        return 0
    fi

    local cherry=0 skip=0 missing=0
    local lines=() line sha subject touched_src

    while IFS= read -r line; do
        lines+=("$line")
    done < <(git -C "$repo" log --format="%H %s" "$base_pin..$head_pin" -- $path_args)

    for line in "${lines[@]}"; do
        [[ -n "$line" ]] || continue
        sha="${line%% *}"
        subject="${line#* }"

        if [[ -n "${svm_subjects[$subject]+x}" ]]; then
            printf "    %s  %s\n" "$(green 'OK')" "$subject"
            cherry_picked_subjects["$subject"]=1
            cherry=$((cherry + 1))
        elif echo "$subject" | grep -qP '^build\(deps\):|^chore\(deps\):'; then
            printf "    %s  %s\n" "$(dim '--')" "$subject"
            skip=$((skip + 1))
        else
            touched_src=$(git -C "$repo" diff-tree --no-commit-id --name-only -r "$sha" -- $path_args \
                | grep -v 'Cargo\.\(toml\|lock\)$' | head -1 || echo "")

            if [[ -z "$touched_src" ]]; then
                printf "    %s  %s\n" "$(dim '--')" "$subject"
                skip=$((skip + 1))
            else
                printf "    %s  %s\n" "$(red '??')" "$subject"

                if $SHOW_DIFF; then
                    echo "        Files in $name SVM paths:"
                    git -C "$repo" diff-tree --no-commit-id --name-only -r "$sha" -- $path_args \
                        | sed 's/^/          /'
                    echo ""
                fi

                missing=$((missing + 1))
            fi
        fi
    done

    echo ""
    printf "    Cherry-picked:         %d\n" "$cherry"
    printf "    Skipped (dep/cargo):   %d\n" "$skip"
    if [[ $missing -gt 0 ]]; then
        printf "    $(red 'Unaccounted:           %d')\n" "$missing"
    else
        printf "    Unaccounted:           %d\n" "$missing"
    fi

    TOTAL_CHERRY=$((TOTAL_CHERRY + cherry))
    TOTAL_SKIP=$((TOTAL_SKIP + skip))
    TOTAL_MISSING=$((TOTAL_MISSING + missing))
    [[ $missing -gt 0 ]] && EXIT_CODE=1

    return 0
}

# Per-upstream pin range resolution + audit.
declare -A BASE_PIN=()
declare -A HEAD_PIN=()

resolve_upstream() {
    local name="$1" repo="$2" head_override="$3" pkg="$4"
    local base_pin head_pin

    [[ -d "$repo/.git" ]] || die "$name repo not found at $repo (use --$name-repo or --upstream to skip)"

    if [[ -n "$head_override" ]]; then
        head_pin="$head_override"
    else
        head_pin=$(get_pin "$pkg" "$HEAD_REF")
        [[ -n "$head_pin" ]] || die "Could not extract $name rev pin from Cargo.toml at $HEAD_REF. Use --$name-ref."
    fi
    git -C "$repo" cat-file -t "$head_pin" >/dev/null 2>&1 \
        || die "$name repo does not contain commit $head_pin — try: git -C $repo fetch"

    base_pin=$(get_pin "$pkg" "$BASE_REF")
    [[ -n "$base_pin" ]] || die "Could not extract $name rev pin from Cargo.toml at $BASE_REF. Use --base-ref."
    git -C "$repo" cat-file -t "$base_pin" >/dev/null 2>&1 \
        || die "$name repo does not contain commit $base_pin — try: git -C $repo fetch"

    BASE_PIN[$name]="$base_pin"
    HEAD_PIN[$name]="$head_pin"
}

if want_upstream agave; then
    resolve_upstream agave "$AGAVE_REPO" "$AGAVE_REF" "agave-feature-set"
fi
if want_upstream sbpf; then
    resolve_upstream sbpf "$SBPF_REPO" "$SBPF_REF" "solana-sbpf"
fi

echo "$(bold 'SVM <-> Upstream Commit Audit')"
echo ""
echo "  SVM head ref:   $HEAD_REF"
echo "  SVM base ref:   $(echo "$BASE_REF" | head -c 12)"
if want_upstream agave; then
    echo "  Agave range:    ${BASE_PIN[agave]}..${HEAD_PIN[agave]}   (repo: $AGAVE_REPO)"
fi
if want_upstream sbpf; then
    echo "  sbpf range:     ${BASE_PIN[sbpf]}..${HEAD_PIN[sbpf]}   (repo: $SBPF_REPO)"
fi
echo ""

echo "  $(bold 'Legend:')"
echo "    [cherry-picked]  [dep-bump/cargo-only]  [?missing]"

if want_upstream agave; then
    echo ""
    echo "$(bold "--- Agave audit (${BASE_PIN[agave]}..${HEAD_PIN[agave]}) ---")"
    audit_upstream agave "$AGAVE_REPO" "${BASE_PIN[agave]}" "${HEAD_PIN[agave]}"
fi

if want_upstream sbpf; then
    echo ""
    echo "$(bold "--- sbpf audit (${BASE_PIN[sbpf]}..${HEAD_PIN[sbpf]}) ---")"
    audit_upstream sbpf "$SBPF_REPO" "${BASE_PIN[sbpf]}" "${HEAD_PIN[sbpf]}"
fi

echo ""
echo "  $(bold 'Aggregate:')"
printf "    Cherry-picked:         %d\n" "$TOTAL_CHERRY"
printf "    Skipped (dep/cargo):   %d\n" "$TOTAL_SKIP"
if [[ $TOTAL_MISSING -gt 0 ]]; then
    printf "    $(red 'Unaccounted:           %d')\n" "$TOTAL_MISSING"
else
    printf "    Unaccounted:           %d\n" "$TOTAL_MISSING"
fi

# SVM-only commits that didn't match any upstream cherry-pick.
echo ""
echo "  $(bold 'SVM-only maintenance commits:')"
has_maintenance=false
while IFS= read -r subject; do
    [[ -n "$subject" ]] || continue
    if [[ -z "${cherry_picked_subjects[$subject]+x}" ]]; then
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
    parts=()
    want_upstream agave && parts+=("agave ${BASE_PIN[agave]:0:12}..${HEAD_PIN[agave]:0:12}")
    want_upstream sbpf  && parts+=("sbpf ${BASE_PIN[sbpf]:0:12}..${HEAD_PIN[sbpf]:0:12}")
    echo "$(green 'PASS') — all upstream commits accounted for: ${parts[*]}"
else
    echo "$(yellow 'UNACCOUNTED COMMITS') — review output above"
    echo ""
    echo "Use --diff to see files touched by unaccounted commits."
fi

exit $EXIT_CODE
