#!/usr/bin/env python3
"""Compile the two changed public bodies against admitted source/DI products and run actual corrected inputs."""
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
parser.add_argument('--groups', default='ordinary')
parser.add_argument('--reuse-build', type=Path)
parser.add_argument('--reuse-port', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
evidence = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
coinc = evidence / 'CS-POLY-COINC-01' / args.lane
ordinary = evidence / 'CS-POLY-01-ordinary' / args.lane
portable = args.lane in {'wasm', 'embedded'}
checks, fresh, runs = {}, {}, []
changed = ['Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift',
    'Sources/CADGeometry/NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift']


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
assert receipt['success'] and receipt['lane'] == args.lane
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
replaced = {str(root / name) for name in changed + [
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
if (coinc / 'reused-port-compilation.json').exists():
    compilation = read(coinc / 'reused-port-compilation.json')
    assert compilation['compileRun']['exitCode'] == 0
    admit(coinc / 'reused-port-compile.log', compilation['compileRun']['logSHA256'])
for name, expected in receipt['production'].items():
    if name not in changed:
        admit(root / name, expected)
for name in changed:
    fresh[str(root / name)] = sha(root / name)

proof_command = read(coinc / 'proof-command.json')
port_command = read(coinc / 'port-command.json')
toolchain = read(coinc / 'toolchain.json')
assert 'swift-6.4.0-RELEASE.xctoolchain' in proof_command[0]
admit(proof_command[0], toolchain['compilerSHA256'])
admit(Path(proof_command[0]).with_name('swift-frontend'), sha(Path(proof_command[0]).with_name('swift-frontend')))
producer_name = 'OriginalRetainedLiftPlanePublicProducer.swift'
producer = next(Path(name) for name in port_command if name.endswith(producer_name))
producer_snapshot = Path(port_snapshots[str(producer)]['path'])
prefix = producer_snapshot.read_text().split('///', 1)[0]
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/CorrectedPolylineLiftPlaneAcceptance.swift'
checks[str(fixture)] = sha(fixture)
checks[str(Path(__file__).resolve())] = sha(__file__)
(out / 'driver.py').write_bytes(Path(__file__).read_bytes())
checks[str(out / 'driver.py')] = sha(out / 'driver.py')


def execute(label, arguments, timeout):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (timeout, timeout))
    log = out / (label + '.log')
    start = time.monotonic()
    with log.open('w') as stream:
        with subprocess.Popen(arguments, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=constrain) as process:
            descendants = set()
            def collect_descendants():
                rows = subprocess.run(['ps', '-axo', 'pid=,ppid='], capture_output=True, text=True, check=True).stdout
                pairs = [tuple(map(int, row.split())) for row in rows.splitlines() if row.strip()]
                owners = {process.pid} | descendants
                while True:
                    found = {pid for pid, parent in pairs if parent in owners}
                    if found <= owners:
                        break
                    owners |= found
                descendants.update(owners - {process.pid})
            try:
                while process.poll() is None:
                    collect_descendants()
                    remaining = timeout - (time.monotonic() - start)
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(arguments, timeout)
                    try:
                        process.wait(timeout=min(1, remaining))
                    except subprocess.TimeoutExpired:
                        pass
                code = process.returncode
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                code = 'timeout'
            finally:
                collect_descendants()
                for child in descendants:
                    command = subprocess.run(['ps', '-p', str(child), '-o', 'command='], capture_output=True, text=True).stdout
                    if str(out) in command:
                        try:
                            os.kill(child, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    runs.append(dict(label=label, command=arguments, timeoutSeconds=timeout, cpuLimitSeconds=timeout,
        exitCode=code, elapsedSeconds=time.monotonic() - start, logSHA256=sha(log)))
    save(out / 'runs.json', runs)
    checks[str(log)] = sha(log)
    print(args.lane, label, code, round(runs[-1]['elapsedSeconds'], 3), flush=True)
    if code != 0:
        print(log.read_text()[-12000:])
        raise SystemExit(1)
    return log.read_text()


def recheck():
    for name, expected in checks.items():
        assert sha(name) == expected, name
    for name, expected in fresh.items():
        assert sha(name) == expected, name


build = args.reuse_build.resolve() if args.reuse_build else out
if args.reuse_build:
    previous = read(build / 'build-receipt.json')
    assert previous['freshProduction'] == fresh
    assert previous['fixtureSHA256'] == sha(fixture)
    for name, expected in previous['checks'].items():
        admit(name, expected)
else:
    port_build = args.reuse_port.resolve() if args.reuse_port else out
    if args.reuse_port:
        previous = read(port_build / 'build-receipt.json')
        assert previous['freshProduction'] == fresh
        mutable = {str(fixture), str(Path(__file__).resolve())}
        for name, expected in previous['checks'].items():
            if name not in mutable:
                admit(name, expected)
        save(out / 'reused-port.json', dict(receipt=str(port_build / 'build-receipt.json'),
            receiptSHA256=sha(port_build / 'build-receipt.json')))
    else:
        compile_port = []
        for argument in port_command:
            if argument.endswith('.swift'):
                original = next((name for name in changed if argument.endswith(Path(name).name)), None)
                if original:
                    path = out / Path(original).name
                    path.write_text(prefix + (root / original).read_text())
                    checks[str(path)] = sha(path)
                    compile_port.append(str(path))
                else:
                    compile_port.append(port_snapshots[argument]['path'] if argument in port_snapshots else argument)
            else:
                compile_port.append(argument)
        compile_port[compile_port.index('-o') + 1] = str(out / 'libPublicLiftPlanePort.a')
        compile_port[compile_port.index('-emit-module-path') + 1] = str(out / 'PublicLiftPlanePort.swiftmodule')
        if '-num-threads' in compile_port:
            for index, option in enumerate(compile_port):
                if option == '-num-threads':
                    compile_port[index + 1] = '2'
        save(out / 'compile-port.json', compile_port)
        execute('compile-port', compile_port, 300 if args.lane == 'embedded' else 120)
        for name in ['libPublicLiftPlanePort.a', 'PublicLiftPlanePort.swiftmodule']:
            checks[str(out / name)] = sha(out / name)
    generated = out / 'Proof.swift'
    generated.write_text(prefix + fixture.read_text())
    checks[str(generated)] = sha(generated)
    support = [name for name in proof_command if name.endswith('.swift') and any(name.endswith(suffix) for suffix in [
        'Fixture0.swift', 'Fixture1.swift', 'Regression-OriginalParametricGraphIssuing.swift',
        'Regression-DefaultOriginalRationalGraphIssuer.swift', 'Regression-DefaultOriginalRationalGraphFamilyPreparer.swift'])]
    assert len(support) == 5
    for name in support:
        admit(name, sha(name))
    flags = [value for value in proof_command[:proof_command.index('-emit-executable')]
        if value not in {'-DPUBLIC_PROOF_SUBNORMAL', '-DPUBLIC_PROOF_CONTAINED_ALL', '-DPUBLIC_PROOF_ALL_MODES'}]
    flags[1:1] = ['-I', str(port_build)]
    archives = [str(port_build / 'libPublicLiftPlanePort.a') if name.endswith('libPublicLiftPlanePort.a') else name
        for name in proof_command if name.endswith('.a')]
    for name in archives:
        assert name in checks, name
    for index, option in enumerate(flags):
        if option == '-num-threads':
            flags[index + 1] = '2'
    # Retain target-specific link options from the admitted proof command.
    link = []
    for index in range(proof_command.index('-emit-executable') + 1, len(proof_command)):
        if proof_command[index] in {'-Xlinker', '-Xclang-linker'}:
            link += proof_command[index:index + 2]
    product = out / ('Proof.wasm' if portable else 'Proof')
    compile_proof = flags + link + ['-emit-executable', str(generated), *support, *archives, '-o', str(product)]
    save(out / 'compile-proof.json', compile_proof)
    execute('compile-proof', compile_proof, 300 if args.lane == 'embedded' else 120)
    checks[str(product)] = sha(product)
    recheck()
    save(out / 'build-receipt.json', dict(freshProduction=fresh, fixtureSHA256=sha(fixture), checks=checks, runs=runs))
product = build / ('Proof.wasm' if portable else 'Proof')
groups = ['ordinary', 'selections', 'query-work', 'query-storage', 'depth', 'cancel-entry', 'cancel-callbacks', 'cancel-final', 'lifetime']
selected = groups if args.groups == 'all' else args.groups.split(',')
assert all(group in groups for group in selected)
runtime = [str(product)]
if portable:
    runner = root / 'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'
    node = '/usr/local/bin/node'
    for name in [node, str(runner)]:
        admit(name, sha(name))
    runtime = [node, str(runner), str(product)]
recheck()
save(out / 'admission.json', dict(checks=checks, freshProduction=fresh,
    parentReceipt=str(coinc / 'receipt.json'), parentSHA256=sha(coinc / 'receipt.json'), replacedHistoricalInputs=sorted(replaced)))
save(out / 'ready-to-run.json', dict(checks=checks, freshProduction=fresh, groups=selected, runs=runs))
for group in selected:
    observed = execute('runtime-' + group, runtime + [group], 120)
    assert 'PASS corrected' in observed, observed
    recheck()
save(out / 'receipt.json', dict(state='changed-public-path-verified', lane=args.lane, cell='CS-POLY-CORRECTION-01',
    checks=checks, freshProduction=fresh, groups=selected, runs=runs,
    parentReceipt=str(coinc / 'receipt.json'), parentSHA256=sha(coinc / 'receipt.json'),
    scope='Two current public producer/publication bodies and actual ordinary corrected-host fixture against admitted source/DI and lower exact artifacts; only listed groups and lane verified.'))
