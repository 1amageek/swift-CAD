#!/usr/bin/env python3
"""Observe one frozen angular public cell with matched independent Native assembly."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
parent = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-REVOLUTION-AXIS-FIBER-01/acceptance/native-20261012-v16/receipt.json'
receipt = json.loads(parent.read_text())
assert receipt['success']
checks, runs, historical = {}, [], {}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def admit(path, expected):
    path = Path(path)
    assert path.is_file() and sha(path) == expected, str(path)
    checks[str(path)] = expected

def save(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

admit(parent, sha(parent))
for path, expected in receipt['checks'].items():
    if path == str(root / 'Tests/OriginalPublicAcceptanceVerification/RevolutionAxisFiberAcceptance.py') and sha(path) != expected:
        archived = root / '.build/cs-revolution-axis-acceptance-native-20261012-v16/RevolutionAxisFiberAcceptance.py'
        admit(archived, expected)
        historical[path] = dict(path=str(archived), sha256=expected,
            scope='Immutable prior runner comparator; not current production or this observation runner.')
    else:
        admit(path, expected)
for path, expected in receipt['freshProduction'].items():
    admit(path, expected)
fixture = Path(__file__).with_suffix('.swift')
for path in [fixture, Path(__file__)]:
    admit(path, sha(path))
old = next(run['command'] for run in receipt['runs'] if run['label'] == 'compile-link')
old_proof = Path(next(path for path in old if path.endswith('/Proof.swift')))
original_fixture = root / 'Tests/OriginalPublicAcceptanceVerification/RevolutionAxisFiberAcceptance.swift'
assert old_proof.read_text().endswith(original_fixture.read_text())
prefix = old_proof.read_text()[:-len(original_fixture.read_text())]
probe = out / 'Proof.swift'
probe.write_text(prefix + fixture.read_text())
admit(probe, sha(probe))
product = out / 'Observation'
command = []
for path in old:
    if path.endswith('/Oracle.swift'):
        continue
    if path == str(old_proof):
        path = str(probe)
    command.append(path)
command[command.index('-o') + 1] = str(product)
command[command.index('-module-name') + 1] = 'AngularPhysicalArcPlaneObservation'
command[command.index('-module-cache-path') + 1] = str(out / 'module-cache')
save('compile-command.json', command)
save('premises.json', dict(parentReceipt=str(parent), parentSHA256=sha(parent),
    head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    freshProduction=receipt['freshProduction'], rebuiltLowerBodies=0,
    unchangedUpperBodies=29, ordinaryPublicCalls=1, oracleField='Q(pi)', historicalComparators=historical))

def recheck():
    for path, expected in checks.items():
        assert sha(path) == expected, path

def execute(label, arguments):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
    started = time.monotonic()
    log = out / (label + '.log')
    timed_out = False
    with log.open('w') as stream:
        process = subprocess.Popen(arguments, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
            start_new_session=True, preexec_fn=constrain)
        try:
            process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    record = dict(label=label, command=arguments, exitCode=process.returncode,
        timedOut=timed_out, elapsedSeconds=time.monotonic()-started,
        wallLimitSeconds=120, cpuLimitSecondsPerProcess=120, logSHA256=sha(log))
    runs.append(record)
    admit(log, record['logSHA256'])
    save('runs.json', runs)
    print(label, process.returncode, round(record['elapsedSeconds'], 3), flush=True)
    return process.returncode

recheck()
compiled = execute('compile-link', command)
events = []
if compiled == 0:
    admit(product, sha(product))
    recheck()
    execute('runtime-once', [str(product)])
    for line in (out / 'runtime-once.log').read_text().splitlines():
        if line.startswith('{'):
            events.append(json.loads(line))
    save('observation.json', events)
recheck()
save('receipt.json', dict(cell='CS-ANGULAR-PHYSICAL-ARC-PLANE-01', cellComplete=False,
    observationRecorded=bool(events and events[-1].get('stage') in ['public-result', 'public-failure']),
    parentReceipt=str(parent), parentSHA256=sha(parent), checks=checks,
    historicalComparators=historical,
    freshProduction=receipt['freshProduction'], runs=runs, events=events,
    rebuiltLowerBodies=0, unchangedUpperBodies=29, ordinaryPublicCalls=1 if compiled == 0 else 0,
    scope='One actual ordinary rich Native observation; numerical output alone is not a complete source/domain/image/fiber receipt.'))
