#!/usr/bin/env python3
"""Verify the frozen Coons boundary cells using admitted independent target products."""
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--fixture', choices=['acceptance', 'controls'], default='acceptance')
parser.add_argument('--reuse-module', type=Path)
parser.add_argument('--group', choices=['all', 'closed', 'strict', 'boundary'], default='all')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
portable = args.lane in {'wasm', 'embedded'}
evidence = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
ordinary = evidence / 'CS-POLY-01-ordinary' / args.lane
native = root / 'Tests/OriginalNativeConsumerIntakeVerification/Evidence' / ('consumer-' + args.lane + '-stable')
checks, fresh, runs = {}, {}, []


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


# These historical public-point bodies are not selected by this boundary assembly.
unselected = {str(root / name) for name in [
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift',
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift',
    'Sources/CADGeometry/CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift',
    'Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift']}
# Native lower adapters are not executed: the admitted PublicLiftPlane receipt
# owns all source/DI/graph equality/refinement in the selected path.
unselected_lower = {str(root / name) for name in [
    'Tests/OriginalGraphRelationVerification/Package.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalFiniteBSplineChartPreparer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalOffsetLawIssuer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalSpatialChartIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/OriginalParameterIdentity.swift']}
# The shared compiler is freshly compiled below. These two historical Native
# consumer bodies are not called here; their changed-body regression is separate.
changed_native = {str(root / name) for name in [
    'Sources/CADGeometry/OriginalBoundaryClipping/OriginalExactBoundaryCompiler.swift',
    'Sources/CADGeometry/OriginalBoundaryClipping/DefaultOriginalExactNativeBoundaryClipper.swift',
    'Sources/CADKernel/OriginalBoundaryClipping/OriginalExactFaceBoundaryIssuer.swift']}
parent = read(ordinary / 'receipt.json')
for name, expected in parent['files'].items():
    admit(ordinary / name, expected)
admit(parent['parentReceipt'], parent['parentSHA256'])
lower = read(parent['parentReceipt'])
snapshots = read(ordinary / 'compiler-source-snapshot.json')
for name, expected in (lower['inputs'] | read(ordinary / 'inputs.json')).items():
    if name not in unselected:
        admit(snapshots[name]['path'] if name in snapshots else name, expected)
for name, expected in lower['product'].items():
    admit(name, expected)
for name, expected in lower['logs'].items():
    admit(Path(parent['parentReceipt']).parent / name, expected)
for name, expected in read(ordinary / 'products.json').items():
    admit(name, expected)
consumer = read(native / 'receipt.json')
for group in ['inputs', 'premises', 'cached', 'artifacts', 'products']:
    for name, expected in consumer[group].items():
        if name in changed_native or (group == 'premises' and name in unselected_lower):
            continue
        admit(name, expected)
for name, expected in consumer['logs'].items():
    admit(native / name, expected)
if portable:
    runtime_receipt = root / 'Tests/OriginalNativeConsumerIntakeVerification/Evidence' / (args.lane + '-query-field-accepted') / 'receipt.json'
    runtime_inputs = read(runtime_receipt)['inputs']
    for path in ['/usr/local/bin/node', str(root / 'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs')]:
        admit(path, runtime_inputs[path])

command = read(ordinary / 'compile-ordinary.json')
flags = command[:command.index('-emit-executable')]
link_flags = []
for index in range(command.index('-emit-executable') + 1, len(command)):
    if command[index] in {'-Xlinker', '-Xclang-linker'}:
        link_flags += command[index:index + 2]
kernel = next(run['command'] for run in consumer['runs'] if run['label'] == 'NativeKernelAdapters')
for index, option in enumerate(kernel):
    if option == '-I':
        flags += ['-I', kernel[index + 1]]
port = read(evidence / 'CS-POLY-COINC-01' / args.lane / 'port-command.json')
producer = next(Path(name) for name in port if name.endswith('OriginalRetainedLiftPlanePublicProducer.swift'))
prefix = producer.read_text().split('///', 1)[0] + '\n@testable import CADKernel\nimport HashTreeCollections\n'
names = ['Sources/CADGeometry/OriginalSourceIssuance/OriginalFaceSurfaceBinding.swift',
         'Sources/CADGeometry/OriginalBoundaryClipping/OriginalExactBoundaryCompiler.swift']
names += sorted(str(path.relative_to(root)) for path in (root / 'Sources/CADGeometry/OriginalBoundaryClipping').glob('*IssuedGraph*.swift'))
names += ['Sources/CADKernel/OriginalBoundaryClipping/OriginalExactFaceBoundaryLoops.swift']
names += sorted(str(path.relative_to(root)) for path in (root / 'Sources/CADKernel/OriginalBoundaryClipping').glob('*IssuedGraph*.swift'))
sources = []
(out / 'driver.py').write_bytes(Path(__file__).read_bytes())
for name in names:
    original = root / name
    generated = out / original.name
    generated.write_text(prefix + original.read_text())
    fresh[str(original)] = sha(original)
    checks[str(generated)] = sha(generated)
    sources.append(str(generated))
checks[str(Path(__file__).resolve())] = sha(__file__)


def execute(label, arguments, timeout=240):
    for name, expected in checks.items():
        assert sha(name) == expected, name
    started = time.monotonic()
    log = out / (label + '.log')
    with log.open('w') as stream:
        try:
            result = subprocess.run(arguments, cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 'timeout'
    runs.append(dict(label=label, command=arguments, timeoutSeconds=timeout, exitCode=code,
                     elapsedSeconds=time.monotonic() - started, logSHA256=sha(log)))
    save(out / 'runs.json', runs)
    print(label, code, round(runs[-1]['elapsedSeconds'], 3), flush=True)
    if code != 0:
        print(log.read_text()[-15000:])
        raise SystemExit(1)
    return log


save(out / 'admission.json', dict(checks=checks, freshProduction=fresh,
    excludedUnselectedInputs=sorted(unselected), excludedNativeLowerRuntimeInputs=sorted(unselected_lower),
    changedNativeBodiesRequiringSeparateRegression=sorted(changed_native)))
module = out
if args.reuse_module:
    module = args.reuse_module.resolve()
    previous = read(module / 'module-receipt.json')
    assert previous['freshProduction'] == fresh
    for name, expected in previous['checks'].items():
        admit(name, expected)
    for name in ['libPublicCoonsBoundary.a', 'PublicCoonsBoundary.swiftmodule']:
        assert str(module / name) in previous['checks']
else:
    execute('compile-module', flags + ['-emit-library', '-static', '-emit-module', '-module-name',
        'PublicCoonsBoundary', *sources, '-o', str(out / 'libPublicCoonsBoundary.a'),
        '-emit-module-path', str(out / 'PublicCoonsBoundary.swiftmodule')])
    for name in ['libPublicCoonsBoundary.a', 'PublicCoonsBoundary.swiftmodule']:
        checks[str(out / name)] = sha(out / name)
    module_checks = {name: value for name, value in checks.items() if name != str(Path(__file__).resolve())}
    module_checks.update(fresh)
    module_checks[str(out / 'driver.py')] = sha(out / 'driver.py')
    save(out / 'module-receipt.json', dict(freshProduction=fresh, checks=module_checks, runs=runs))

support = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsHoleBoundaryProbe.swift'
text = support.read_text().replace('@main struct CoonsHoleBoundaryProbe', 'struct CoonsHoleBoundaryProbe')
text = text[:text.index('    static func main() throws {')] + '}\n'
text = text.replace('import NativeDomainAdapters\n', '').replace('import NativeKernelAdapters\n', '')
generated = out / 'Support.swift'
generated.write_text(prefix + text)
fixture = root / 'Tests/OriginalPublicAcceptanceVerification' / ('CoonsHoleBoundaryAcceptance.swift' if args.fixture == 'acceptance' else 'CoonsHoleBoundaryControls.swift')
proof = out / fixture.name
proof.write_text(prefix + fixture.read_text())
for path in [support, generated, fixture, proof]:
    checks[str(path)] = sha(path)
fixture_sources = [name for name in command if name.endswith('.swift') and Path(name).name in {
    'Fixture0.swift', 'Fixture1.swift', 'Regression-OriginalParametricGraphIssuing.swift',
    'Regression-DefaultOriginalRationalGraphIssuer.swift', 'Regression-DefaultOriginalRationalGraphFamilyPreparer.swift'}]
if args.fixture == 'controls':
    helper = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsHoleBoundaryAcceptance.swift'
    generated_helper = out / 'AcceptanceHelper.swift'
    generated_helper.write_text(prefix + helper.read_text().replace('@main struct CoonsHoleBoundaryAcceptance', 'struct CoonsHoleBoundaryAcceptance'))
    for path in [helper, generated_helper]:
        checks[str(path)] = sha(path)
    fixture_sources.append(str(generated_helper))
archives = [name for name in command if name.endswith('.a') and not name.endswith('libPublicLiftPlanePort.a')]
objects = [name for name in consumer['cached'] if name.endswith('.o') and (
    Path(name).name in {'CADTopology.o', 'CADKernel.o'} or Path(name).parent.name in {'CADTopology.build', 'CADKernel.build'})]
product = out / ('Proof.wasm' if portable else 'Proof')
execute('compile-link-' + args.fixture, flags + link_flags + ['-I', str(module), '-emit-executable', str(generated), str(proof),
    *fixture_sources, str(module / 'libPublicCoonsBoundary.a'), *archives, *objects, '-o', str(product)])
checks[str(product)] = sha(product)
runtime = [str(product), args.group]
if portable:
    runtime = ['/usr/local/bin/node', str(root / 'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'), str(product), args.group]
    for name in runtime[:2]:
        assert name in checks, 'Runtime must be admitted by the target receipt: ' + name
execute('runtime-' + args.fixture, runtime, timeout=360)
for name, expected in checks.items():
    assert sha(name) == expected, name
for name, expected in fresh.items():
    assert sha(name) == expected, name
save(out / 'receipt.json', dict(state='changed-path-' + args.fixture + '-verified', lane=args.lane,
    freshProduction=fresh, checks=checks, runs=runs,
    scope='Original exact-validated four-cell Coons face, source/DI graph and public Kernel parameter/material result. No general-family, Native shared-body regression, M7 XYZ or full-cell delivery claim.'))
