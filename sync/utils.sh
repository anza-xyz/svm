#!/usr/bin/env bash
#
# utils.sh — Shared utilities for SVM sync verification scripts.
#
# Sourced by verify-tree.sh and verify-commits.sh. Not executable on its own.
#

# Every crate directory in the SVM repo, in display order. Each is verified
# against its Agave counterpart (same path, or overridden in AGAVE_PATH below).
SVM_PATHS=(
    bls12-381-syscall
    callback
    compute-budget
    feature-set
    log-collector
    measure
    program-binaries
    program-runtime
    programs/bpf_loader
    programs/compute-budget
    programs/loader-v4
    programs/sbf
    programs/system
    svm
    svm-test-harness
    syscalls
    timings
    transaction
    transaction-context
    type-overrides
)

# Some crates live under different directory names in Agave (typically prefixed
# with svm-). This map translates SVM path -> Agave path for those cases.
# Crates not listed here have the same path in both repos.
declare -A AGAVE_PATH=(
    [callback]=svm-callback
    [feature-set]=svm-feature-set
    [log-collector]=svm-log-collector
    [measure]=svm-measure
    [timings]=svm-timings
    [transaction]=svm-transaction
    [type-overrides]=svm-type-overrides
)

# Look up the Agave-side path for a given SVM path. Returns the override if
# one exists, otherwise returns the input unchanged.
agave_path_for() { echo "${AGAVE_PATH[$1]:-$1}"; }

# Extract the Agave rev pin from Cargo.toml at a given git ref. The workspace
# Cargo.toml has git dependencies like:
#   agave-foo = { git = "...", rev = "abc123" }
# This grabs the first `rev = "..."` value, which is the Agave commit SHA that
# the SVM workspace is pinned to.
get_agave_pin() {
    git show "$1:Cargo.toml" 2>/dev/null \
        | grep -m1 'rev = "' \
        | sed 's/.*rev = "\([^"]*\)".*/\1/'
}

red()    { printf '\033[1;31m%s\033[0m' "$*"; }
green()  { printf '\033[1;32m%s\033[0m' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m' "$*"; }
dim()    { printf '\033[2m%s\033[0m' "$*"; }
bold()   { printf '\033[1m%s\033[0m' "$*"; }

die() { echo "ERROR: $*" >&2; exit 2; }
