#!/usr/bin/env python3
"""Check final main composition and execute admitted focused products without rebuilding."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--evidence-root', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
original = args.evidence_root.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
checks = {}
receipts = {}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(path, expected):
    path = Path(path)
    if digest(path) != expected:
        raise RuntimeError('Changed integration premise: ' + str(path))
    checks[str(path)] = expected


for lane in ['native', 'asan', 'wasm', 'embedded']:
    receipt_path = original / 'Tests/OriginalRollingBallIntakeVerification/Evidence' / lane / 'receipt.json'
    receipt = json.loads(receipt_path.read_text())
    receipts[lane] = receipt
    require(receipt_path, digest(root / receipt_path.relative_to(original)))
    for name, expected in receipt['inputs'].items():
        path = Path(name)
        if path.is_relative_to(original):
            require(root / path.relative_to(original), expected)
        require(path, expected)
    for kind in ['products', 'logs']:
        for name, expected in receipt[kind].items():
            require(name, expected)

runs = []
for lane in ['native', 'embedded']:
    accepted = next(run for run in receipts[lane]['commands'] if run['label'] == 'runtime')
    start = time.monotonic()
    result = subprocess.run(accepted['command'], capture_output=True, text=True, timeout=120)
    log = output / (lane + '-runtime.log')
    log.write_text(result.stdout + result.stderr)
    run = dict(lane=lane, command=accepted['command'], timeoutSeconds=120,
               elapsedSeconds=time.monotonic()-start, exitCode=result.returncode,
               log=str(log), logSHA256=digest(log))
    runs.append(run)
    (output / 'runs.json').write_text(json.dumps(runs, indent=2)+'\n')
    print(lane, result.returncode, round(run['elapsedSeconds'],3), flush=True)
    if result.returncode:
        print(result.stderr[-7000:])
        raise SystemExit(result.returncode)
for name, expected in list(checks.items()):
    require(name, expected)
record = dict(root=str(root), implementationHead=subprocess.check_output(
    ['git','rev-parse','HEAD'],cwd=root,text=True).strip(), checks=checks, runs=runs,
    driverSHA256=digest(__file__), scope='Independent latest-main composition; no rebuild or additional aggregate review.')
(output / 'integration.json').write_text(json.dumps(record, indent=2)+'\n')
print('PASS integration premises', len(checks), flush=True)
