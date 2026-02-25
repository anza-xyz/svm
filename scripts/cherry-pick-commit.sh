#!/usr/bin/env bash
set -euo pipefail

UPSTREAM="${UPSTREAM_CLONE:?set UPSTREAM_CLONE to the path of the upstream repo clone}"

usage() {
    echo "Usage: $(basename "$0") <hash> [-- path1 path2 ...]" >&2
    exit 1
}

[[ $# -lt 1 ]] && usage

hash="$1"
shift

paths=()
if [[ $# -gt 0 && "$1" == "--" ]]; then
    shift
    paths=("$@")
fi

if ! git -C "$UPSTREAM" cat-file -e "${hash}^{commit}" 2>/dev/null; then
    echo "error: commit $hash not found in $UPSTREAM" >&2
    exit 1
fi

author_name=$(git -C "$UPSTREAM" log -1 --format="%an" "$hash")
author_email=$(git -C "$UPSTREAM" log -1 --format="%ae" "$hash")
author_date=$(git -C "$UPSTREAM" log -1 --format="%aD" "$hash")
author_ts=$(git -C "$UPSTREAM" log -1 --format="%at" "$hash")
committer_name=$(git -C "$UPSTREAM" log -1 --format="%cn" "$hash")
committer_email=$(git -C "$UPSTREAM" log -1 --format="%ce" "$hash")
committer_date=$(git -C "$UPSTREAM" log -1 --format="%cD" "$hash")
message=$(git -C "$UPSTREAM" log -1 --format="%B" "$hash")

apply_upstream() {
    if [[ ${#paths[@]} -gt 0 ]]; then
        git -C "$UPSTREAM" diff "${hash}^".."${hash}" -- "${paths[@]}" | git apply --index
    else
        git -C "$UPSTREAM" diff "${hash}^".."${hash}" | git apply --index
    fi
}

commit_with_meta() {
    local _author_name="$1" _author_email="$2" _author_date="$3"
    local _committer_name="$4" _committer_email="$5" _committer_date="$6"
    local _message="$7"
    GIT_AUTHOR_NAME="$_author_name" GIT_AUTHOR_EMAIL="$_author_email" GIT_AUTHOR_DATE="$_author_date" \
    GIT_COMMITTER_NAME="$_committer_name" GIT_COMMITTER_EMAIL="$_committer_email" GIT_COMMITTER_DATE="$_committer_date" \
        git commit -m "$_message"
}

apply_upstream
commit_with_meta \
    "$author_name" "$author_email" "$author_date" \
    "$committer_name" "$committer_email" "$committer_date" \
    "$message"

# Find the insertion point: last branch commit whose author timestamp <= new commit's
insertion_point=""
while IFS=" " read -r h t; do
    [[ "$t" -le "$author_ts" ]] && insertion_point="$h"
done < <(git log --reverse --format="%H %at" master..HEAD^)

# Collect branch commits that must come after the new one
to_replay=()
recording=false
[[ -z "$insertion_point" ]] && recording=true
while IFS= read -r h; do
    "$recording" && to_replay+=("$h")
    [[ "$h" == "$insertion_point" ]] && recording=true
done < <(git log --reverse --format="%H" master..HEAD^)

[[ ${#to_replay[@]} -eq 0 ]] && exit 0

echo "Reordering: moving before ${#to_replay[@]} later commit(s)..."

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

for h in "${to_replay[@]}"; do
    git log -1 --format="%an|%ae|%aD|%cn|%ce|%cD" "$h" > "$tmp/$h.meta"
    git log -1 --format="%B" "$h" > "$tmp/$h.msg"
    git diff "$h^" "$h" > "$tmp/$h.patch"
done

if [[ -z "$insertion_point" ]]; then
    git reset --hard "$(git merge-base master HEAD)"
else
    git reset --hard "$insertion_point"
fi

apply_upstream
commit_with_meta \
    "$author_name" "$author_email" "$author_date" \
    "$committer_name" "$committer_email" "$committer_date" \
    "$message"

for h in "${to_replay[@]}"; do
    IFS="|" read -r r_author_name r_author_email r_author_date r_committer_name r_committer_email r_committer_date \
        < "$tmp/$h.meta"
    git apply --index < "$tmp/$h.patch"
    commit_with_meta \
        "$r_author_name" "$r_author_email" "$r_author_date" \
        "$r_committer_name" "$r_committer_email" "$r_committer_date" \
        "$(cat "$tmp/$h.msg")"
done
