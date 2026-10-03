#!/usr/bin/env bash

set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "usage: $0 <source-path> [source-path ...]" >&2
    exit 64
fi

pattern='(?ms)deinit[[:space:]]*\{(?:(?!^[[:space:]]*\}).)*(syncShutdownGracefully|\.wait\(|semaphore)'
if rg --multiline --pcre2 --line-number "$pattern" "$@"; then
    echo "synchronous shutdown or waiting from deinit is not allowed" >&2
    exit 1
fi

echo "no synchronous shutdown or waiting from deinit found"
