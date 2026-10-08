#!/usr/bin/env bash
set -euo pipefail
exec python3 - "$@" <<'PYTHON'
import os
import signal
import subprocess
import sys

arguments = sys.argv[1:]
if len(arguments) < 3 or arguments[1] != "--":
    sys.exit("usage: swift-test-timeout.sh <seconds: 1...120> -- <command> [arguments...]")
try:
    seconds = int(arguments[0])
except ValueError:
    sys.exit("timeout must be an integer from 1 through 120 seconds")
if not 1 <= seconds <= 120:
    sys.exit("timeout must be an integer from 1 through 120 seconds")
process = subprocess.Popen(arguments[2:], start_new_session=True)

def stop_group(signum):
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass

try:
    result = process.wait(timeout=seconds)
except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
    print(f"bounded command stopped: {error}", file=sys.stderr)
    stop_group(signal.SIGTERM)
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    stop_group(signal.SIGKILL)
    process.wait()
    sys.exit(124 if isinstance(error, subprocess.TimeoutExpired) else 130)
else:
    # The command owns its process group, including compiler and test helpers.
    # Descendants must not survive a completed or failed bounded invocation.
    stop_group(signal.SIGTERM)
    stop_group(signal.SIGKILL)
    sys.exit(result if result >= 0 else 128 - result)
PYTHON
