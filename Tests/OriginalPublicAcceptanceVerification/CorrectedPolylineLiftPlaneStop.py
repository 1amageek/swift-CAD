#!/usr/bin/env python3
"""Observe the actual corrected-host exact entry decline using admitted Native products."""
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
evidence = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
coinc = evidence / 'CS-POLY-COINC-01/native'
ordinary = evidence / 'CS-POLY-01-ordinary/native'
checks, runs = {}, []


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


receipt = read(coinc / 'receipt.json')
assert receipt['success'] and receipt['lane'] == 'native'
admit(coinc / 'receipt.json', sha(coinc / 'receipt.json'))
for name, expected in receipt['files'].items():
    admit(coinc / name, expected)
for name, expected in receipt['products'].items():
    admit(name, expected)
for name, expected in receipt['sharedCompilerSources'].items():
    admit(name, expected)
for run in receipt['runs']:
    admit(coinc / (run['label'] + '.log'), run['logSHA256'])
normal_path = Path(receipt['parentReceipt'])
admit(normal_path, receipt['parentSHA256'])
normal = read(normal_path)
for name, expected in normal['files'].items():
    admit(normal_path.parent / name, expected)
admit(normal['parentReceipt'], normal['parentSHA256'])
parent = read(ordinary / 'receipt.json')
for name, expected in parent['files'].items():
    admit(ordinary / name, expected)
admit(parent['parentReceipt'], parent['parentSHA256'])
lower = read(parent['parentReceipt'])
snapshots = read(ordinary / 'compiler-source-snapshot.json')
replaced = {str(root / name) for name in [
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift',
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift',
    'Sources/CADGeometry/CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift',
    'Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift']}
for name, expected in (lower['inputs'] | read(ordinary / 'inputs.json')).items():
    if name not in replaced:
        admit(snapshots[name]['path'] if name in snapshots else name, expected)
for name, expected in lower['product'].items():
    admit(name, expected)
for name, expected in lower['logs'].items():
    admit(Path(parent['parentReceipt']).parent / name, expected)
for name, expected in read(ordinary / 'products.json').items():
    admit(name, expected)
port_snapshots = read(coinc / 'compiler-source-snapshot.json')
for name, expected in read(coinc / 'compiler-inputs.json').items():
    admit(port_snapshots[name]['path'] if name in port_snapshots else name, expected)
compilation = read(coinc / 'reused-port-compilation.json')
assert compilation['compileRun']['exitCode'] == 0
admit(coinc / 'reused-port-compile.log', compilation['compileRun']['logSHA256'])
for name, expected in receipt['production'].items():
    admit(root / name, expected)

command = read(coinc / 'proof-command.json')
flags = [value for value in command[:command.index('-emit-executable')] if value != '-DPUBLIC_PROOF_SUBNORMAL']
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
toolchain = read(coinc / 'toolchain.json')
admit(flags[0], toolchain['compilerSHA256'])
admit(Path(flags[0]).with_name('swift-frontend'), sha(Path(flags[0]).with_name('swift-frontend')))
producer_name = 'OriginalRetainedLiftPlanePublicProducer.swift'
producer = next(Path(name) for name in read(coinc / 'port-command.json') if name.endswith(producer_name))
compiled_producer = Path(port_snapshots[str(producer)]['path']).read_text()
current_producer = root / 'Sources/CADGeometry/NativeExactGeometricRelations' / producer_name
assert compiled_producer.count(current_producer.read_text()) == 1
assert 'case .procedural(.originalCoons) = input.surface else { return nil }' in current_producer.read_text()
prefix = compiled_producer.split('///', 1)[0]
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/CorrectedPolylineLiftPlaneStop.swift'
generated = out / 'Probe.swift'
generated.write_text(prefix + fixture.read_text())
checks[str(fixture)] = sha(fixture)
checks[str(generated)] = sha(generated)
checks[str(Path(__file__).resolve())] = sha(__file__)
(out / 'driver.py').write_bytes(Path(__file__).read_bytes())
checks[str(out / 'driver.py')] = sha(out / 'driver.py')
support = [name for name in command if name.endswith('.swift') and any(name.endswith(suffix) for suffix in [
    'Fixture0.swift', 'Fixture1.swift', 'Regression-OriginalParametricGraphIssuing.swift',
    'Regression-DefaultOriginalRationalGraphIssuer.swift', 'Regression-DefaultOriginalRationalGraphFamilyPreparer.swift'])]
assert len(support) == 5
for name in support:
    admit(name, sha(name))
archives = [name for name in command if name.endswith('.a')]
for name in archives:
    assert name in checks, name
save(out / 'admission.json', dict(checks=checks, parentReceipt=str(coinc / 'receipt.json'),
    selectedCurrentProducer={str(current_producer): sha(current_producer)},
    replacedHistoricalPublicInputs=sorted(replaced)))


def execute(label, arguments, timeout):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (timeout, timeout))
    log = out / (label + '.log')
    start = time.monotonic()
    with log.open('w') as stream:
        with subprocess.Popen(arguments, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=constrain) as process:
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                code = 'timeout'
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    runs.append(dict(label=label, command=arguments, timeoutSeconds=timeout, cpuLimitSeconds=timeout,
        exitCode=code, elapsedSeconds=time.monotonic() - start, logSHA256=sha(log)))
    save(out / 'runs.json', runs)
    checks[str(log)] = sha(log)
    print(label, code, round(runs[-1]['elapsedSeconds'], 3), flush=True)
    if code != 0:
        print(log.read_text()[-12000:])
        raise SystemExit(1)
    return log.read_text()


def recheck():
    for name, expected in checks.items():
        assert sha(name) == expected, name


product = out / 'Probe'
execute('compile-link', flags + ['-emit-executable', str(generated), *support, *archives, '-o', str(product)], 120)
checks[str(product)] = sha(product)
recheck()
save(out / 'ready-to-run.json', dict(checks=checks, runs=runs))
observed = execute('runtime-selected-producer', [str(product)], 120)
recheck()
assert 'PASS actual corrected constructor/source/DI;' in observed
if observed.count('OBSERVED selected exact public producer declined corrected host') == 2:
    state = 'reproduced-selected-producer-decline'
elif observed.count('OBSERVED selected exact public producer accepted corrected host') == 2:
    state = 'producer-accepted'
else:
    raise AssertionError(observed)
save(out / 'receipt.json', dict(state=state, lane='native', cell='CS-POLY-CORRECTION-01', checks=checks, runs=runs,
    parentReceipt=str(coinc / 'receipt.json'), parentSHA256=sha(coinc / 'receipt.json'),
    scope='Actual corrected original constructor/source/DI and exact root/XYZ/UV oracle, followed by direct invocation of the current exact public entry producer in bare/rich modes. No fallback public dispatcher or relation re-solve, no target-lane acceptance.'))
print(state, flush=True)
