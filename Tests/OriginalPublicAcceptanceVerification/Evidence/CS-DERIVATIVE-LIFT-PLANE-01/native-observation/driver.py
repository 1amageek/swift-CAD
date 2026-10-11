#!/usr/bin/env python3
"""Observe the current Native exact entry without rebuilding admitted lower proofs."""
import argparse
import hashlib
import json
import os
import resource
import signal
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
checks, runs, historical = {}, [], {}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def admit(path, expected):
    path = Path(path)
    assert sha(path) == expected, str(path)
    checks[str(path)] = expected


def recheck():
    for name, expected in checks.items():
        assert sha(name) == expected, name


derivative_path = root / 'Tests/OriginalDerivativeLiftHostVerification/Evidence/native/receipt.json'
derivative = read(derivative_path)
assert derivative['success'] and derivative['lane'] == 'native'
admit(derivative_path, sha(derivative_path))
for name, expected in derivative['inputs'].items():
    path = Path(name)
    if path.is_file() and sha(path) == expected:
        admit(path, expected)
    else:
        # These cached numerical-module sources predate the current public dispatcher.
        # Recover only receipt-matching original bytes; no current-source equivalence is inferred.
        relative = path.relative_to(root)
        commit = 'ff67aa6d093ee717cc299573e0687d4263ac5f36' if path.name == 'OriginalRollingBallGraphProducer.swift' else 'd963399f'
        content = subprocess.check_output(['git', 'show', commit + ':' + str(relative)], cwd=root)
        assert hashlib.sha256(content).hexdigest() == expected, name
        snapshot = out / 'historical-source' / relative
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        snapshot.write_bytes(content)
        admit(snapshot, expected)
        historical[name] = dict(path=str(snapshot), commit=commit, sha256=expected)
for name, expected in derivative['product'].items():
    admit(name, expected)
for name, expected in derivative['logs'].items():
    admit(derivative_path.parent / name, expected)
assert all(run['exitCode'] == 0 for run in derivative['runs'])

port = root / '.build/cs-poly-correction-native-20261011-v1'
port_path = port / 'build-receipt.json'
previous = read(port_path)
admit(port_path, sha(port_path))
assert all(run['exitCode'] == 0 for run in previous['runs'])
mutable = {str(root / 'Tests/OriginalPublicAcceptanceVerification' / name) for name in [
    'CorrectedPolylineLiftPlaneAcceptance.swift', 'CorrectedPolylineLiftPlane.py']}
for name, expected in previous['checks'].items():
    if name not in mutable:
        admit(name, expected)
for name, expected in previous['freshProduction'].items():
    admit(name, expected)
port_command = next(run['command'] for run in previous['runs'] if run['label'] == 'compile-port')
for name in port_command:
    if name.endswith('.swift'):
        assert name in checks, name
        for relative in previous['freshProduction']:
            if name.endswith(Path(relative).name):
                assert Path(name).read_text().count(Path(relative).read_text()) == 1
tripwire = next(Path(name) for name in port_command if name.endswith('UnselectedOverlapTripwire.swift'))
assert 'throw Failure.unselectedLegacyRoute' in tripwire.read_text()
ordinary = next(Path(name) for name in port_command if name.endswith('DefaultCurveSurfaceIntersector+Overlap.swift'))
current_ordinary = root / 'Sources/CADGeometry/CurveSurfaceOverlap/DefaultCurveSurfaceIntersector+Overlap.swift'
assert ordinary.read_text().count(current_ordinary.read_text()) == 1
admit(current_ordinary, sha(current_ordinary))

old_command = next(run['command'] for run in previous['runs'] if run['label'] == 'compile-proof')
flags = old_command[:old_command.index('-emit-executable')]
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
assert '-j2' in flags and flags[flags.index('-target') + 1] == 'arm64-apple-macos15.0'
assert flags[0] in checks
frontend = Path(flags[0]).with_name('swift-frontend')
admit(frontend, sha(frontend))
sdk = flags[flags.index('-sdk') + 1]
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/DerivativeLiftPlaneStop.swift'
shape = root / 'Tests/OriginalDerivativeLiftHostVerification/Shape.swift'
assert str(shape) in checks
admit(fixture, sha(fixture))
admit(Path(__file__).resolve(), sha(__file__))
(out / 'driver.py').write_bytes(Path(__file__).read_bytes())
admit(out / 'driver.py', sha(out / 'driver.py'))
(out / 'Probe.swift').write_bytes(fixture.read_bytes())
admit(out / 'Probe.swift', sha(fixture))
archives = [name for name in old_command if name.endswith('.a')]
assert all(name in checks for name in archives)
product = out / 'Probe'
command = flags + ['-emit-executable', str(out / 'Probe.swift'), str(shape), *archives, '-o', str(product)]
save(out / 'compile-command.json', command)
admit(out / 'compile-command.json', sha(out / 'compile-command.json'))
save(out / 'admission.json', dict(checks=checks, derivativeReceipt=str(derivative_path),
    portReceipt=str(port_path), historicalSources=historical,
    excludedMutableVerificationPaths=sorted(mutable), toolchain=flags[0], sdk=sdk,
    scope='Current exact producer and ordinary rich selected body; verification tripwire fallback. No lower proof rerun.'))


def execute(label, arguments):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
    log = out / (label + '.log')
    started = time.monotonic()
    descendants, peak_rss, cpu_by_pid = set(), 0, {}
    with log.open('w') as stream:
        with subprocess.Popen(arguments, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=constrain) as process:
            def sample():
                nonlocal peak_rss
                lines = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss=,time='], text=True).splitlines()
                rows = [line.split() for line in lines if line.strip()]
                owners = {process.pid} | descendants
                while True:
                    found = {int(pid) for pid, parent, rss, cpu in rows if int(parent) in owners}
                    if found <= owners:
                        break
                    owners |= found
                descendants.update(owners - {process.pid})
                peak_rss = max(peak_rss, sum(int(rss) for pid, parent, rss, cpu in rows if int(pid) in owners))
                for pid, parent, rss, cpu in rows:
                    if int(pid) in owners:
                        seconds = sum(float(value) * 60 ** index for index, value in enumerate(reversed(cpu.split(':'))))
                        cpu_by_pid[int(pid)] = max(cpu_by_pid.get(int(pid), 0), seconds)
                return {int(pid) for pid, parent, rss, cpu in rows}
            timed_out = False
            while process.poll() is None:
                sample()
                if time.monotonic() - started >= 120:
                    timed_out = True
                    break
                try:
                    process.wait(timeout=0.25)
                except subprocess.TimeoutExpired:
                    pass
            alive = sample()
            survivors = descendants & alive
            if timed_out or survivors:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                for pid in survivors:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            process.wait()
            remaining = descendants & sample()
    run = dict(label=label, command=arguments, exitCode=process.returncode, timedOut=timed_out,
        elapsedSeconds=time.monotonic() - started, wallLimitSeconds=120, cpuLimitSecondsPerProcess=120,
        sampledCPUSeconds=sum(cpu_by_pid.values()), peakOwnedProcessResidentSumKiB=peak_rss,
        ownedDescendantsRemaining=sorted(remaining), logSHA256=sha(log))
    runs.append(run)
    save(out / 'runs.json', runs)
    admit(log, run['logSHA256'])
    assert process.returncode == 0 and not timed_out and not remaining, run


state = 'assembly-not-executed'
try:
    recheck()
    execute('compile-probe', command)
    admit(product, sha(product))
    recheck()
    save(out / 'runtime-admission.json', dict(checks=checks))
    execute('observation', [str(product)])
    output = (out / 'observation.log').read_text()
    if 'SELECTED_PRODUCER_DECLINED' in output and 'ASSEMBLY_STOP' in output:
        state = 'selected-producer-declined-and-verification-fallback-assembly-stop'
    else:
        state = 'public-observation-recorded-see-log'
finally:
    recheck()
    save(out / 'receipt.json', dict(observationComplete=state != 'assembly-not-executed', cellComplete=False,
        state=state, checks=checks, runs=runs, historicalSources=historical,
        derivativeReceipt=str(derivative_path), derivativeReceiptSHA256=sha(derivative_path),
        portReceipt=str(port_path), portReceiptSHA256=sha(port_path),
        scope='Actual current exact-entry selection and rich-body fallthrough only; production fallback unobserved.'))
print(state, flush=True)
