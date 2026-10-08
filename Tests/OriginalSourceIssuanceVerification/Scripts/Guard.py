#!/usr/bin/env python3
"""Bound one isolated verification command and preserve its complete output."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--timeout', type=int, default=120)
parser.add_argument('--log', required=True, type=Path)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
args.log.parent.mkdir(parents=True, exist_ok=True)
start = time.monotonic()
with args.log.open('w') as log:
    log.write('COMMAND: ' + repr(command) + '\n')
    log.flush()
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        code = process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        code = 124
    log.write(f'\nEXIT: {code}; SECONDS: {time.monotonic() - start:.3f}\n')
print(args.log.read_text()[-16000:])
raise SystemExit(code)
