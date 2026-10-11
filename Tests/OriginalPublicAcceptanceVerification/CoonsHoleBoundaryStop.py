#!/usr/bin/env python3
"""Reproduce the frozen Coons-to-public-boundary binding stop without broad builds."""
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.build/b-coons-hole-stop-native-20261011'
out.mkdir(parents=True, exist_ok=False)
evidence = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
ordinary = evidence / 'CS-POLY-01-ordinary/native'
native = root / 'Tests/OriginalNativeConsumerIntakeVerification/Evidence/consumer-native-stable'
checks = {}
runs = []


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def record(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def admit(path, expected):
    path = Path(path)
    assert sha(path) == expected, str(path)
    checks[str(path)] = expected


parent = read(ordinary / 'receipt.json')
for name, expected in parent['files'].items():
    admit(ordinary / name, expected)
admit(parent['parentReceipt'], parent['parentSHA256'])
lower = read(parent['parentReceipt'])
inputs = lower['inputs'] | read(ordinary / 'inputs.json')
snapshots = read(ordinary / 'compiler-source-snapshot.json')
# These four historical public-point inputs are not compiled, linked or called.
unused = {str(root / name) for name in [
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift',
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift',
    'Sources/CADGeometry/CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift',
    'Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift']}
for name, expected in inputs.items():
    if name in unused:
        continue
    path = snapshots[name]['path'] if name in snapshots else name
    admit(path, expected)
for name, expected in lower['product'].items():
    admit(name, expected)
for name, expected in lower['logs'].items():
    admit(Path(parent['parentReceipt']).parent / name, expected)
for name, expected in read(ordinary / 'products.json').items():
    admit(name, expected)
consumer = read(native / 'receipt.json')
unselected_native_lower = {str(root / name) for name in [
    'Tests/OriginalGraphRelationVerification/Package.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalFiniteBSplineChartPreparer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalOffsetLawIssuer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalSpatialChartIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/OriginalParameterIdentity.swift']}
# Native lower modules supply only the rejected input's signature. The runtime
# uses the separately admitted PublicLiftPlane source/DI/L5 and original Topology.
for group in ['inputs', 'premises', 'cached', 'artifacts', 'products']:
    for name, expected in consumer[group].items():
        if group == 'premises' and name in unselected_native_lower:
            continue
        admit(name, expected)
for name, expected in consumer['logs'].items():
    admit(native / name, expected)

command = read(ordinary / 'compile-ordinary.json')
flags = command[:command.index('-emit-executable')]
kernel = next(run['command'] for run in consumer['runs'] if run['label'] == 'NativeKernelAdapters')
for index, option in enumerate(kernel):
    if option == '-I':
        flags += ['-I', kernel[index + 1]]
production = root / 'Sources/CADKernel/OriginalBoundaryClipping'
bound = ['OriginalExactFaceBoundaryClipping.swift', 'DefaultOriginalFaceBoundaryClipper+Exact.swift',
         'OriginalExactFaceBoundaryIssuer.swift']
for name in bound:
    assert str(production / name) in consumer['inputs']

port = read(evidence / 'CS-POLY-COINC-01/native/port-command.json')
producer = next(Path(name) for name in port if name.endswith('OriginalRetainedLiftPlanePublicProducer.swift'))
prefix = producer.read_text().split('///', 1)[0]
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsHoleBoundaryProbe.swift'
generated = out / 'Probe.swift'
generated.write_text(prefix + fixture.read_text())
sources = [str(generated)] + [name for name in command if name.endswith('.swift') and Path(name).name in {
    'Fixture0.swift', 'Fixture1.swift', 'Regression-OriginalParametricGraphIssuing.swift',
    'Regression-DefaultOriginalRationalGraphIssuer.swift', 'Regression-DefaultOriginalRationalGraphFamilyPreparer.swift'}]
for name in [str(fixture), str(generated), __file__]:
    checks[name] = sha(name)
record(out / 'admission.json', dict(checks=checks, excludedUnselectedInputs=sorted(unused),
    excludedNativeLowerRuntimeInputs=sorted(unselected_native_lower),
    selectedKernelSignatures={name: sha(production / name) for name in bound}))


def run(label, arguments, expected_code=0, timeout=120):
    started = time.monotonic()
    result = subprocess.run(arguments, cwd=root, capture_output=True, text=True, timeout=timeout)
    log = out / (label + '.log')
    log.write_text(result.stdout + result.stderr)
    runs.append(dict(label=label, command=arguments, timeoutSeconds=timeout, exitCode=result.returncode,
                     elapsedSeconds=time.monotonic() - started, logSHA256=sha(log)))
    record(out / 'runs.json', runs)
    print(label, result.returncode, round(runs[-1]['elapsedSeconds'], 3), flush=True)
    if result.returncode != expected_code:
        print(log.read_text()[-12000:])
        raise SystemExit(1)
    return log.read_text()


commands = [flags + ['-typecheck', *sources], flags + ['-typecheck', '-DB_COONS_BINDING_RED', *sources]]
previous = os.environ.get('B_COONS_REUSE_STOP')
if previous:
    previous = Path(previous).resolve()
    previous_runs = read(previous / 'runs.json')
    assert sha(previous / 'Probe.swift') == sha(generated)
    for index, label in enumerate(['typecheck-control', 'typecheck-public-binding-red']):
        accepted = previous_runs[index]
        assert accepted['label'] == label and accepted['exitCode'] == index
        assert [value.replace(str(previous), str(out)) for value in accepted['command']] == commands[index]
        admit(previous / (label + '.log'), accepted['logSHA256'])
        runs.append(accepted)
    diagnostic = (previous / 'typecheck-public-binding-red.log').read_text()
else:
    run('typecheck-control', commands[0])
    diagnostic = run('typecheck-public-binding-red', commands[1], expected_code=1)
assert len(re.findall(r':\d+:\d+: error:', diagnostic)) == 1, diagnostic
assert 'cannot convert value of type' in diagnostic and 'NativeExactParametricRelations' in diagnostic, diagnostic
print(diagnostic, flush=True)
archives = [name for name in command if name.endswith('.a') and not name.endswith('libPublicLiftPlanePort.a')]
topology = next(name for name in consumer['cached'] if name.endswith('/CADTopology.o'))
product = out / 'probe'
run('compile-link-original-input', flags + ['-emit-executable', *sources, *archives, topology, '-o', str(product)])
checks[str(product)] = sha(product)
run('runtime-original-input', [str(product)])
for name, expected in checks.items():
    assert sha(name) == expected, name
record(out / 'receipt.json', dict(state='reproduced-stop', cells=[
    'B-COONS-HOLE-CLOSED-01', 'B-COONS-HOLE-STRICT-01', 'B-COONS-HOLE-BOUNDARY-01'],
    sourceSHA256=sha(fixture), inputs=checks, runs=runs,
    scope='Native exact original constructor/validated Coons face/complete source-DI graph input and public Native boundary binding compiler rejection. No boundary success or full-cell acceptance claim.'))
