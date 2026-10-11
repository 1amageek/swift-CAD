#!/usr/bin/env python3
"""Reproduce the frozen Coons-to-public-self-contact stop without broad builds."""
import hashlib
import json
import os
import signal
import resource
import re
import subprocess
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.build/s-coons-plane-stop-native-20261011'
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
unselected_native_bodies = {str(root / name) for name in [
    'Sources/CADGeometry/NativeExactRelations/DefaultNativeExactRelationFamilyResolver.swift',
    'Sources/CADGeometry/OriginalBoundaryClipping/DefaultOriginalExactNativeBoundaryClipper.swift',
    'Sources/CADGeometry/OriginalBoundaryClipping/OriginalExactBoundaryCompiler.swift',
    'Sources/CADKernel/OriginalBoundaryClipping/OriginalExactFaceBoundaryIssuer.swift']}
unselected_native_lower = {str(root / name) for name in [
    'Tests/OriginalGraphRelationVerification/Package.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalFiniteBSplineChartPreparer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalOffsetLawIssuer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalSpatialChartIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/OriginalParameterIdentity.swift']}
# Native lower modules supply only the rejected input's signature. The runtime
# uses the separately admitted PublicLiftPlane source/DI/L5 only; no Native self consumer body executes.
for group in ['inputs', 'premises', 'cached', 'artifacts', 'products']:
    for name, expected in consumer[group].items():
        if group == 'inputs' and name in unselected_native_bodies:
            continue
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
production = root / 'Sources/CADGeometry/OriginalSurfaceEmbedding'
bound = ['DefaultOriginalExactNativeSelfContactQuery.swift']
for name in bound:
    assert str(production / name) in consumer['inputs']

port = read(evidence / 'CS-POLY-COINC-01/native/port-command.json')
producer = next(Path(name) for name in port if name.endswith('OriginalRetainedLiftPlanePublicProducer.swift'))
prefix = producer.read_text().split('///', 1)[0]
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsGraphSelfContactProbe.swift'
generated = out / 'Probe.swift'
generated.write_text(prefix + fixture.read_text())
sources = [str(generated)] + [name for name in command if name.endswith('.swift') and Path(name).name in {
    'Fixture0.swift', 'Fixture1.swift', 'Regression-OriginalParametricGraphIssuing.swift',
    'Regression-DefaultOriginalRationalGraphIssuer.swift', 'Regression-DefaultOriginalRationalGraphFamilyPreparer.swift'}]
# Check the actual selected compiler paths as well as their archived snapshots.
for name in sources[1:]:
    admit(name, snapshots[name]['sha256'])
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
for name in [str(fixture), str(generated), str(producer), flags[0],
             str(Path(flags[0]).with_name('swift-frontend')), __file__]:
    checks[name] = sha(name)
record(out / 'admission.json', dict(checks=checks, excludedUnselectedInputs=sorted(unused),
    excludedNativeBodiesNotCompiledLinkedOrCalled=sorted(unselected_native_bodies),
    excludedNativeLowerRuntimeInputs=sorted(unselected_native_lower),
    selectedRejectedNativeSelfSignature={name: sha(production / name) for name in bound}))


def run(label, arguments, expected_code=0, timeout=120):
    started = time.monotonic()
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (240, 240))
    process = subprocess.Popen(arguments, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True, preexec_fn=constrain)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        rows = subprocess.check_output(['ps', '-axo', 'pid,ppid,command'], text=True).splitlines()[1:]
        parsed = [row.split(None, 2) for row in rows]
        descendants = {process.pid}
        for _ in range(len(parsed)):
            updated = descendants | {int(row[0]) for row in parsed if len(row) == 3 and int(row[1]) in descendants}
            if updated == descendants:
                break
            descendants = updated
        for pid in descendants:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stdout, stderr = process.communicate()
        (out / (label + '.log')).write_text(stdout + stderr + '\nOwned process timeout.\n')
        raise SystemExit('Timed out: ' + label)
    result = subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)
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


commands = [flags + ['-typecheck', *sources], flags + ['-typecheck', '-DS_COONS_SELF_RED', *sources]]
run('typecheck-control', commands[0])
diagnostic = run('typecheck-public-self-red', commands[1], expected_code=1)
assert len(re.findall(r':\d+:\d+: error:', diagnostic)) == 1, diagnostic
assert 'cannot convert value of type' in diagnostic and 'NativeExactParametricRelations' in diagnostic, diagnostic
print(diagnostic, flush=True)
archives = [name for name in command if name.endswith('.a') and not name.endswith('libPublicLiftPlanePort.a')]
product = out / 'probe'
run('compile-link-original-input', flags + ['-emit-executable', *sources, *archives, '-o', str(product)])
checks[str(product)] = sha(product)
runtime = run('runtime-original-input', [str(product)])
assert 'all 16 chart pairs equal the complete independent closed-domain diagonal oracle' in runtime
for name, expected in checks.items():
    assert sha(name) == expected, name
record(out / 'receipt.json', dict(state='reproduced-stop', cells=[
    'S-COONS-PLANE-01'],
    sourceSHA256=sha(fixture), inputs=checks, runs=runs,
    scope='Native actual original four-chart planar Coons full self product and all16 closed-domain whole-cell diagonal oracle; public Native-only self-contact signature compiler rejection. No residual-query implementation, embedding certification or caller migration success claim.'))
