#!/usr/bin/env python3
"""Compile only the changed self consumer against receipt-admitted original graph products."""
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
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--fixture', default='CoonsGraphSelfContactAcceptance.swift')
parser.add_argument('--reuse-module', type=Path)
parser.add_argument('--group', default='all')
parser.add_argument('--groups', nargs='+')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
portable = args.lane in {'wasm', 'embedded'}
evidence = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
ordinary = evidence / 'CS-POLY-01-ordinary' / args.lane
checks, fresh, runs = {}, {}, []

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(path):
    return json.loads(Path(path).read_text())

def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')

def admit(path, expected):
    assert sha(path) == expected, str(path)
    checks[str(path)] = expected

parent = read(ordinary / 'receipt.json')
for name, expected in parent['files'].items():
    admit(ordinary / name, expected)
admit(parent['parentReceipt'], parent['parentSHA256'])
lower = read(parent['parentReceipt'])
snapshots = read(ordinary / 'compiler-source-snapshot.json')
unused = {str(root / name) for name in [
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift',
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift',
    'Sources/CADGeometry/CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift',
    'Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift']}
for name, expected in (lower['inputs'] | read(ordinary / 'inputs.json')).items():
    if name not in unused:
        admit(snapshots[name]['path'] if name in snapshots else name, expected)
for name, expected in lower['product'].items():
    admit(name, expected)
for name, expected in lower['logs'].items():
    admit(Path(parent['parentReceipt']).parent / name, expected)
for name, expected in read(ordinary / 'products.json').items():
    admit(name, expected)
# The actual Coons assembly already contains the current M5 authored/view bodies.
m5 = {}
for name in ['DefaultOriginalParameterIdentityIssuer.swift', 'OriginalParameterIdentity.swift', 'OriginalParameterIdentityRelation.swift']:
    path = root / 'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity' / name
    expected = lower['inputs'][str(path)]
    admit(path, expected)
    m5[str(path)] = expected
command = read(ordinary / 'compile-ordinary.json')
flags = command[:command.index('-emit-executable')]
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
for path in [flags[0], str(Path(flags[0]).with_name('swift-frontend'))]:
    checks[path] = sha(path)
link_flags = []
for index in range(command.index('-emit-executable') + 1, len(command)):
    if command[index] in {'-Xlinker', '-Xclang-linker'}:
        link_flags += command[index:index + 2]
port = read(evidence / 'CS-POLY-COINC-01' / args.lane / 'port-command.json')
producer = next(Path(name) for name in port if name.endswith('OriginalRetainedLiftPlanePublicProducer.swift'))
prefix = producer.read_text().split('///', 1)[0]
checks[str(producer)] = sha(producer)
production = root / 'Sources/CADGeometry/OriginalSurfaceEmbedding'
names = ['OriginalIssuedGraphSelfContactQuerying.swift', 'OriginalIssuedGraphSelfContacts.swift',
         'DefaultOriginalIssuedGraphSelfContactQuery.swift', 'OriginalIssuedGraphSelfIdentityCompiler.swift']
sources = []
for name in names:
    original, generated = production / name, out / name
    generated.write_text(prefix + original.read_text())
    fresh[str(original)] = sha(original)
    checks[str(generated)] = sha(generated)
    sources.append(str(generated))
(out / 'driver.py').write_bytes(Path(__file__).read_bytes())
checks[str(out / 'driver.py')] = sha(__file__)


def execute(label, arguments):
    runtime = label.startswith('runtime')
    timeout, cpu_limit = (360, 360) if runtime else (240, 240)
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (cpu_limit, cpu_limit))
    start = time.monotonic()
    log = out / (label + '.log')
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
    runs.append(dict(label=label, command=arguments, timeoutSeconds=timeout, cpuLimitSeconds=cpu_limit,
        exitCode=code, elapsedSeconds=time.monotonic() - start, logSHA256=sha(log)))
    save(out / 'runs.json', runs)
    print(label, code, round(runs[-1]['elapsedSeconds'], 3), flush=True)
    if code != 0:
        print(log.read_text()[-15000:])
        raise SystemExit(1)

save(out / 'admission.json', dict(checks=checks, freshProduction=fresh, unchangedM5=m5,
    excludedUnselectedInputs=sorted(unused)))
module = args.reuse_module.resolve() if args.reuse_module else out
if args.reuse_module:
    previous = read(module / 'module-receipt.json')
    assert previous['freshProduction'] == fresh
    for path, expected in previous['checks'].items():
        admit(path, expected)
else:
    execute('compile-module', flags + ['-emit-library', '-static', '-emit-module', '-module-name',
        'PublicCoonsSelf', *sources, '-o', str(out / 'libPublicCoonsSelf.a'),
        '-emit-module-path', str(out / 'PublicCoonsSelf.swiftmodule')])
    for name in ['libPublicCoonsSelf.a', 'PublicCoonsSelf.swiftmodule']:
        checks[str(out / name)] = sha(out / name)
    save(out / 'module-receipt.json', dict(freshProduction=fresh, checks=checks, runs=runs))
support = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsGraphSelfContactProbe.swift'
text = support.read_text().replace('@main struct CoonsGraphSelfContactProbe', 'struct CoonsGraphSelfContactProbe')
text = text[:text.index('    static func main() throws {')] + '}\n'
text = text.replace('import NativeDomainAdapters\n', '')
generated = out / 'Support.swift'
generated.write_text(prefix + text)
fixture = root / 'Tests/OriginalPublicAcceptanceVerification' / args.fixture
proof = out / fixture.name
proof.write_text(prefix + fixture.read_text())
for path in [support, generated, fixture, proof]:
    checks[str(path)] = sha(path)
fixture_sources = [name for name in command if name.endswith('.swift') and Path(name).name in {
    'Fixture0.swift', 'Fixture1.swift', 'Regression-OriginalParametricGraphIssuing.swift',
    'Regression-DefaultOriginalRationalGraphIssuer.swift', 'Regression-DefaultOriginalRationalGraphFamilyPreparer.swift'}]
for name in fixture_sources:
    admit(name, snapshots[name]['sha256'])
archives = [name for name in command if name.endswith('.a') and not name.endswith('libPublicLiftPlanePort.a')]
product = out / ('Proof.wasm' if portable else 'Proof')
execute('compile-link-proof', flags + link_flags + ['-I', str(module), '-emit-executable',
    str(generated), str(proof), *fixture_sources, str(module / 'libPublicCoonsSelf.a'), *archives, '-o', str(product)])
checks[str(product)] = sha(product)
runtime = [str(product)]
if portable:
    prior = root / 'Tests/OriginalNativeConsumerIntakeVerification/Evidence' / (args.lane + '-query-field-accepted') / 'receipt.json'
    runtime_inputs = read(prior)['inputs']
    runner = root / 'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'
    for path in ['/usr/local/bin/node', str(runner)]:
        admit(path, runtime_inputs[path])
    runtime = ['/usr/local/bin/node', str(runner), str(product)]
for path, expected in checks.items():
    assert sha(path) == expected, path
for path, expected in fresh.items():
    assert sha(path) == expected, path
groups = args.groups or [args.group]
save(out / 'ready-to-run.json', dict(checks=checks, freshProduction=fresh, runs=runs,
    runtime=runtime, groups=groups))
for group in groups:
    assert sha(product) == checks[str(product)]
    for path, expected in fresh.items():
        assert sha(path) == expected, path
    execute('runtime-' + group, runtime + [group])
for path, expected in checks.items():
    assert sha(path) == expected, path
for path, expected in fresh.items():
    assert sha(path) == expected, path
save(out / 'receipt.json', dict(state='changed-path-verified', lane=args.lane, checks=checks,
    freshProduction=fresh, unchangedM5=m5, runs=runs,
    scope='Original Coons source/DI graph self product to public residual parameter self-contact result; no embedding/caller or aggregate completion.'))
