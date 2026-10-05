#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 4 || "$3" != "--" ]]; then
    echo "usage: $0 <repeat-count> <seconds: 1...120> -- <command> [arguments...]" >&2
    exit 64
fi

repeat_count="$1"
timeout_seconds="$2"
shift 3

if ! [[ "$repeat_count" =~ ^[0-9]+$ ]] || (( repeat_count < 1 )); then
    echo "repeat count must be a positive integer" >&2
    exit 64
fi

script_directory="$(cd "$(dirname "$0")" && pwd)"
lock_key="$(pwd | cksum | awk '{print $1}')"
lock_directory="${TMPDIR:-/tmp}/swift-cad-test-hang-guard-${lock_key}.lock"
if ! mkdir "$lock_directory" 2>/dev/null; then
    echo "another bounded test run is active for this working directory" >&2
    exit 3
fi
trap 'rmdir "$lock_directory" 2>/dev/null || true' EXIT

for run_index in $(seq 1 "$repeat_count"); do
    echo "bounded test run ${run_index}/${repeat_count}"
    "$script_directory/swift-test-timeout.sh" "$timeout_seconds" -- "$@"
done
