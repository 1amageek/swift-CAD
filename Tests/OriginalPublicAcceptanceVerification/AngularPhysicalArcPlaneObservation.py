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
parser.add_argument('--artifacts', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
artifacts = args.artifacts.resolve()
assert artifacts.is_relative_to(root / '.build')
artifacts.mkdir(parents=True, exist_ok=False)
parent = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-REVOLUTION-AXIS-FIBER-01/acceptance/native-20261012-v16/receipt.json'
receipt = json.loads(parent.read_text())
assert receipt['success']
checks, runs, historical = {}, [], {}
resolver = root / 'Sources/CADGeometry/CurveSurfaceOverlap/CurveSurfaceOverlapResolver.swift'
old_resolver_sha = '2bdd731fbf46142816f3784fc1dd13020eec57e53334d0d80d85048a89e04843'
new_resolver_sha = 'e314106b7eedb65c4581b522e03d4ec0304a26a31e48e358a3159fcd97eaf8a7'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def admit(path, expected):
    path = Path(path)
    assert path.is_file() and sha(path) == expected, str(path)
    checks[str(path)] = expected

def save(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def admit_parent(path, expected):
    if Path(path) == resolver:
        assert expected == old_resolver_sha
        admit(resolver, new_resolver_sha)
    else:
        admit(path, expected)

admit(parent, '2562317fd283a1301aa5c54dfc2bcc06f1d22242b4708f979dce082fd1ee3eaf')
prior = out.parent / 'native-observation-20261012-v2'
admit(prior / 'receipt.json', 'b78b854fdacd065f5a234b54e5c131c4d8790aa51227115785b797da66829406')
admit(prior / 'artifact-locations.json', '35947e8047c750c96f4cfc7220f28950320da1f67ec03bd1d6a70fe803d52705')
for path, expected in receipt['checks'].items():
    if path == str(root / 'Tests/OriginalPublicAcceptanceVerification/RevolutionAxisFiberAcceptance.py') and sha(path) != expected:
        archived = root / '.build/cs-revolution-axis-acceptance-native-20261012-v16/RevolutionAxisFiberAcceptance.py'
        admit(archived, expected)
        historical[path] = dict(path=str(archived), sha256=expected,
            scope='Immutable prior runner comparator; not current production or this observation runner.')
    else:
        admit_parent(path, expected)
for path, expected in receipt['freshProduction'].items():
    admit_parent(path, expected)
fresh = dict(receipt['freshProduction'])
fresh[str(resolver)] = new_resolver_sha
fixture = Path(__file__).with_suffix('.swift')
for path in [fixture, Path(__file__)]:
    admit(path, sha(path))
admit(fixture, 'db481aff37f081787dfc60a6fbf512e35f3cbdd4a78b32f0eb73695a5f021d35')
old = next(run['command'] for run in receipt['runs'] if run['label'] == 'compile-link')
old_proof = Path(next(path for path in old if path.endswith('/Proof.swift')))
original_fixture = root / 'Tests/OriginalPublicAcceptanceVerification/RevolutionAxisFiberAcceptance.swift'
assert old_proof.read_text().endswith(original_fixture.read_text())
prefix = old_proof.read_text()[:-len(original_fixture.read_text())]
probe = out / 'Proof.swift'
probe.write_text(prefix + fixture.read_text())
admit(probe, sha(probe))
old_resolver = Path(next(path for path in old if path.endswith('/CurveSurfaceOverlapResolver.swift')))
admit(old_resolver, 'c825445e0e3bb27d075f685efe2e9a15315129bdcde14685e1382d44dde1e5ee')
old_bytes = old_resolver.read_bytes()
body_start = old_bytes.rfind(b'import CADCore\n#if !hasFeature(Embedded)\n')
assert body_start >= 0
assert hashlib.sha256(old_bytes[body_start:]).hexdigest() == old_resolver_sha
resolver_prefix = old_bytes[:body_start]
new_resolver = out / 'CurveSurfaceOverlapResolver.swift'
new_resolver.write_bytes(resolver_prefix + resolver.read_bytes())
admit(new_resolver, sha(new_resolver))
replacement = dict(originalPath=str(resolver), oldSHA256=old_resolver_sha,
    newSHA256=new_resolver_sha, originalCompilerInput=str(old_resolver),
    originalCompilerInputSHA256=sha(old_resolver), importPrefixSHA256=hashlib.sha256(resolver_prefix).hexdigest(),
    compilerInput=str(new_resolver), compilerInputSHA256=sha(new_resolver),
    transformation='Exact archived import prefix followed by the approved current original resolver body.')
product = artifacts / 'Observation'
command = []
for path in old:
    if path.endswith('/Oracle.swift'):
        continue
    if path == str(old_proof):
        path = str(probe)
    if path == str(old_resolver):
        path = str(new_resolver)
    command.append(path)
command[command.index('-o') + 1] = str(product)
command[command.index('-module-name') + 1] = 'AngularPhysicalArcPlaneObservation'
command[command.index('-module-cache-path') + 1] = str(artifacts / 'module-cache')
save('compile-command.json', command)
save('premises.json', dict(parentReceipt=str(parent), parentSHA256=sha(parent),
    head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    freshProduction=fresh, sourceReplacement=replacement, rebuiltLowerBodies=0,
    unchangedUpperBodies=28, changedUpperBodies=1, ordinaryPublicCalls=1,
    artifactDirectory=str(artifacts), oracleField='Q(pi)', historicalComparators=historical))

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
    freshProduction=fresh, sourceReplacement=replacement, runs=runs, events=events,
    artifactDirectory=str(artifacts), rebuiltLowerBodies=0, unchangedUpperBodies=28,
    changedUpperBodies=1, ordinaryPublicCalls=1 if compiled == 0 else 0,
    scope='One actual ordinary rich Native observation; numerical output alone is not a complete source/domain/image/fiber receipt.'))
