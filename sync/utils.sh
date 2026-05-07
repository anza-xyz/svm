#!/usr/bin/env bash
#
# utils.sh — Shared utilities for SVM sync verification scripts.
#
# Sourced by verify-tree.sh, verify-commits.sh, and update-rev-pins.sh.
# Not executable on its own.
#
# The SVM repo tracks two upstreams:
#   * agave — anza-xyz/agave (filtered to SVM-owned crate paths)
#   * sbpf  — anza-xyz/sbpf  (subtree-merged into the sbpf/ directory)
#
# The UPSTREAM map below tags each crate path with the upstream it came from.

# Every crate directory in the SVM repo, in display order. Each is verified
# against its upstream counterpart (same path, or overridden in the upstream's
# rename map).
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
    sbpf
    svm
    svm-test-harness
    syscalls
    timings
    transaction
    transaction-context
    type-overrides
)

# Tag every path with its upstream.
declare -A UPSTREAM=(
    [bls12-381-syscall]=agave
    [callback]=agave
    [compute-budget]=agave
    [feature-set]=agave
    [log-collector]=agave
    [measure]=agave
    [program-binaries]=agave
    [program-runtime]=agave
    [programs/bpf_loader]=agave
    [programs/compute-budget]=agave
    [programs/loader-v4]=agave
    [programs/sbf]=agave
    [programs/system]=agave
    [sbpf]=sbpf
    [svm]=agave
    [svm-test-harness]=agave
    [syscalls]=agave
    [timings]=agave
    [transaction]=agave
    [transaction-context]=agave
    [type-overrides]=agave
)

# Per-upstream rename maps: SVM path -> upstream-side path.
# Crates not listed have the same path in both repos.
declare -A AGAVE_PATH=(
    [callback]=svm-callback
    [feature-set]=svm-feature-set
    [log-collector]=svm-log-collector
    [measure]=svm-measure
    [timings]=svm-timings
    [transaction]=svm-transaction
    [type-overrides]=svm-type-overrides
)
declare -A SBPF_PATH=( )  # empty for now; reserved for cleanup-time renames

# Look up the upstream-side path for a given SVM path.
upstream_path_for() {
    local svm_path="$1"
    case "${UPSTREAM[$svm_path]:-}" in
        agave) echo "${AGAVE_PATH[$svm_path]:-$svm_path}" ;;
        sbpf)  echo "${SBPF_PATH[$svm_path]:-$svm_path}" ;;
        *)     die "Unknown upstream for path: $svm_path" ;;
    esac
}

# Extract the rev pin for a specific package from Cargo.toml at a given git ref.
# Indexes by package name so the lookup is deterministic regardless of how many
# rev pins the workspace carries. Prints empty (and returns 0) when Cargo.toml
# doesn't exist at the ref or the package isn't pinned to a git rev.
#
# Usage: get_pin <package-name> [ref]
# Example: get_pin agave-feature-set HEAD
#          get_pin solana-sbpf HEAD
get_pin() {
    local pkg="$1" ref="${2:-HEAD}"
    git cat-file -e "$ref:Cargo.toml" 2>/dev/null || return 0
    git show "$ref:Cargo.toml" \
        | grep -m1 -E "^[[:space:]]*${pkg}[[:space:]]*=" \
        | sed -nE 's/.*rev[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
        || true
}

red()    { printf '\033[1;31m%s\033[0m' "$*"; }
green()  { printf '\033[1;32m%s\033[0m' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m' "$*"; }
dim()    { printf '\033[2m%s\033[0m' "$*"; }
bold()   { printf '\033[1m%s\033[0m' "$*"; }

die() { echo "ERROR: $*" >&2; exit 2; }
