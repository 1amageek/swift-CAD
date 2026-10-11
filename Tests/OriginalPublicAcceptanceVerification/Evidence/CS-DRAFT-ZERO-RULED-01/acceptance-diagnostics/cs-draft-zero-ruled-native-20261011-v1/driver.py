#!/usr/bin/env python3
"""Compose the finite draft/line public cell with admitted lower source/DI and L2-L6 products."""
import argparse
import hashlib
import json
import os
import re
import resource
import signal
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--groups', default='ordinary')
parser.add_argument('--reuse-port', type=Path)
parser.add_argument('--reuse-build', type=Path)
parser.add_argument('--diagnostic', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
evidence = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
checks, fresh, runs, historical = {}, {}, [], {}
portable = args.lane in {'wasm', 'embedded'}


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


def admit_historical(name, expected):
    path = Path(name)
    if path.is_file() and sha(path) == expected:
        admit(path, expected)
        return
    relative = path.relative_to(root)
    assert relative.parts[0] in {'Sources', 'Tests'}, name
    for commit in ['9c11fd8d', '5cf82ea2', '99d61ff1', 'd963399f', 'ff67aa6d093ee717cc299573e0687d4263ac5f36']:
        result = subprocess.run(['git', 'show', commit + ':' + str(relative)], cwd=root, capture_output=True)
        if result.returncode == 0 and hashlib.sha256(result.stdout).hexdigest() == expected:
            snapshot = out / 'historical-source' / relative
            snapshot.parent.mkdir(parents=True, exist_ok=True)
            snapshot.write_bytes(result.stdout)
            admit(snapshot, expected)
            historical[name] = dict(path=str(snapshot), commit=commit, sha256=expected)
            return
    raise AssertionError('Missing immutable historical comparator: ' + name)


def recheck():
    for name, expected in checks.items():
        assert sha(name) == expected, name
    for name, expected in fresh.items():
        assert sha(name) == expected, name


# These receipts already proved source/DI and the lower numerical modules.
derivative_path = root / 'Tests/OriginalDerivativeLiftHostVerification/Evidence' / args.lane / 'receipt.json'
derivative = read(derivative_path)
assert derivative['success'] and derivative['lane'] == args.lane
admit(derivative_path, sha(derivative_path))
for name, expected in derivative['inputs'].items():
    admit_historical(name, expected)
for name, expected in derivative['product'].items():
    admit(name, expected)
for name, expected in derivative['logs'].items():
    admit(derivative_path.parent / name, expected)
assert all(run['exitCode'] == 0 for run in derivative['runs'])
derivative_command = next(run['command'] for run in derivative['runs'] if run['label'] == 'compile-adapters')
derivative_module = Path(derivative_command[derivative_command.index('-emit-module-path') + 1]).parent
for name in ['libRetainedHostAdapters.a', 'RetainedHostAdapters.swiftmodule',
        'libDerivativePayloadAccess.a', 'DerivativePayloadAccess.swiftmodule']:
    assert str(derivative_module / name) in checks

# Admit the accepted unchanged algebra archive and its successful compiler inputs/logs.
correction = root / '.build' / ('cs-poly-correction-' + args.lane + '-20261011-' + ('v6' if args.lane == 'embedded' else 'v1'))
prior_path = correction / 'build-receipt.json'
prior = read(prior_path)
admit(prior_path, sha(prior_path))
mutable_verification = {str(root / 'Tests/OriginalPublicAcceptanceVerification' / name) for name in [
    'CorrectedPolylineLiftPlaneAcceptance.swift', 'CorrectedPolylineLiftPlane.py']}
for name, expected in prior['checks'].items():
    if name not in mutable_verification:
        admit_historical(name, expected)
assert all(run['exitCode'] == 0 for run in prior['runs'])
ordinary = evidence / 'CS-POLY-01-ordinary' / args.lane
base_command = read(ordinary / 'command.json')
base_port_command = read(evidence / 'CS-POLY-COINC-01' / args.lane / 'port-command.json')
base_proof = next(run['command'] for run in prior['runs'] if run['label'] == 'compile-proof')
assert 'swift-6.4.0-RELEASE.xctoolchain' in base_command[0]
assert base_command[0] in checks
admit(Path(base_command[0]).with_name('swift-frontend'), sha(Path(base_command[0]).with_name('swift-frontend')))
flags = base_command[:base_command.index('-emit-library')]
algebra_library = Path(next(name for name in base_proof if name.endswith('libPublicLiftPlane.a')))
assert str(algebra_library.with_name('PublicLiftPlane.swiftmodule')) in checks
flags[1:1] = ['-I', str(derivative_module), '-I', str(algebra_library.parent)]
for index, flag in enumerate(flags):
    if flag == '-num-threads':
        flags[index + 1] = '2'

# Every generated body is the current original source, with namespace imports only.
source_by_name = {}
for path in (root / 'Sources/CADGeometry').rglob('*.swift'):
    source_by_name.setdefault(path.name, []).append(path)

def current(name):
    name = re.sub(r'^[0-9a-f]{12}-', '', name)
    candidates = source_by_name.get(name, [])
    assert len(candidates) == 1, (name, candidates)
    return candidates[0]

lower_names = set()
for component in ['ExactRealRoot', 'ExactRealCell', 'ExactRealTopology', 'ExactParametricRelation', 'ExactGeometricRelation']:
    lower_names.update(path.name for path in (root / 'Sources/CADGeometry/RationalBivariateAlgebra' / component).glob('*.swift'))
selected = [current(Path(name).name) for name in base_command if name.endswith('.swift') and Path(name).name not in lower_names]
selected += [current(Path(name).name) for name in base_port_command
    if name.endswith('.swift') and not name.endswith('UnselectedOverlapTripwire.swift')]
selected += [current(name + '.swift') for name in [
    'OriginalPlaneSnapshot', 'OriginalPlaneSnapshotProvider',
    'OriginalPolylinePcurveSnapshot', 'OriginalPolylinePcurveSnapshotProvider',
    'OriginalPolylineRetainedAtlasLiftSnapshot', 'OriginalPolylineRetainedAtlasLiftSnapshotProvider',
    'OriginalDraftedZeroTranslationRationalAtlas', 'OriginalDraftedRuledSurfaceSnapshot',
    'OriginalDraftedRuledSurfaceSnapshotProvider', 'OriginalLinearCurveSnapshot', 'OriginalLinearCurveSnapshotProvider',
    'DefaultOriginalRationalGraphFamilyPreparer', 'OriginalDraftedZeroLinePublicProducer', 'OriginalRationalGraphPointPublisher',
    'OriginalEuclideanPolylineParameterLaw', 'OriginalPolynomialSurfaceLiftGraphReduction',
    'OriginalPolynomialSurfaceLiftGraphReducing', 'DefaultOriginalPolynomialSurfaceLiftGraphReducer']]
selected = list(dict.fromkeys(selected))
local_names = {path.stem for path in selected}

def declarations(paths, module):
    result = []
    for path in paths:
        for kind, name in re.findall(r'^public\s+(?:final\s+)?(struct|class|enum|protocol|typealias)\s+(\w+)', Path(path).read_text(), re.M):
            if name not in local_names:
                result.append('import ' + kind + ' ' + module + '.' + name)
    return result

header = '\n'.join(dict.fromkeys(['import CADCore', '@testable import CADGeometry',
    '@testable import RetainedHostAdapters', 'import struct RetainedHostAdapters.OriginalSourceProofAdmission',
    '@testable import DerivativePayloadAccess', '@testable import PublicLiftPlane']
    + declarations([name for name in derivative_command if name.endswith('.swift')], 'RetainedHostAdapters')
    + declarations([name for name in base_command if name.endswith('.swift') and Path(name).name in lower_names], 'PublicLiftPlane'))) + '\n'
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift'
for path in [fixture, Path(__file__).resolve()]:
    admit(path, sha(path))
(out / 'driver.py').write_bytes(Path(__file__).read_bytes())
admit(out / 'driver.py', sha(out / 'driver.py'))


def execute(label, command, wall, cpu, allow_failure=False):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (cpu, cpu))
    log = out / (label + '.log')
    start = time.monotonic()
    descendants, peak, cpu_by_pid, progress = set(), 0, {}, []
    with log.open('w') as stream:
        with subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=constrain) as process:
            def sample():
                nonlocal peak
                rows = [row.split() for row in subprocess.check_output(
                    ['ps', '-axo', 'pid=,ppid=,rss=,time='], text=True).splitlines() if row.strip()]
                owners = {process.pid} | descendants
                while True:
                    found = {int(pid) for pid, parent, rss, elapsed in rows if int(parent) in owners}
                    if found <= owners:
                        break
                    owners |= found
                descendants.update(owners - {process.pid})
                peak = max(peak, sum(int(rss) for pid, parent, rss, elapsed in rows if int(pid) in owners))
                for pid, parent, rss, elapsed in rows:
                    if int(pid) in owners:
                        seconds = sum(float(value) * 60 ** i for i, value in enumerate(reversed(elapsed.split(':'))))
                        cpu_by_pid[int(pid)] = max(cpu_by_pid.get(int(pid), 0), seconds)
                return {int(pid) for pid, parent, rss, elapsed in rows}
            timed_out, next_update = False, 60
            while process.poll() is None:
                sample()
                elapsed = time.monotonic() - start
                if elapsed >= next_update:
                    record = dict(wallSeconds=elapsed, sampledCPUSeconds=sum(cpu_by_pid.values()), peakRSSKiB=peak)
                    progress.append(record)
                    save(out / (label + '-progress.json'), progress)
                    print(args.lane, label, record, flush=True)
                    next_update += 60
                if elapsed >= wall:
                    timed_out = True
                    break
                try:
                    process.wait(timeout=0.5)
                except subprocess.TimeoutExpired:
                    pass
            survivors = descendants & sample()
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
    run = dict(label=label, command=command, exitCode=process.returncode, timedOut=timed_out,
        elapsedSeconds=time.monotonic() - start, wallLimitSeconds=wall, cpuLimitSecondsPerProcess=cpu,
        sampledCPUSeconds=sum(cpu_by_pid.values()), peakOwnedProcessResidentSumKiB=peak,
        ownedDescendantsRemaining=sorted(remaining), logSHA256=sha(log))
    runs.append(run)
    save(out / 'runs.json', runs)
    admit(log, run['logSHA256'])
    print(args.lane, label, 'exit', process.returncode, 'wall', round(run['elapsedSeconds'], 3), flush=True)
    if not ((process.returncode == 0 or allow_failure) and not timed_out and not remaining):
        recheck()
        save(out / 'failure-receipt.json', dict(success=False, failedOperation=label,
            checks=checks, freshProduction=fresh, runs=runs, postRunAdmission=True,
            scope='Observed selected compile/runtime failure; no geometry completion claim.'))
    assert (process.returncode == 0 or allow_failure) and not timed_out and not remaining, run


compile_wall, compile_cpu = (600, 300) if args.lane == 'embedded' else (120, 120)
build = args.reuse_build.resolve() if args.reuse_build else out
if args.reuse_build:
    previous_path = build / 'build-receipt.json'
    previous = read(previous_path)
    assert previous['fixtureSHA256'] == sha(fixture)
    for name, expected in previous['checks'].items():
        admit(name, expected)
    fresh = previous['freshProduction']
else:
    port = args.reuse_port.resolve() if args.reuse_port else out
    if args.reuse_port:
        previous_path = port / 'port-receipt.json'
        previous = read(previous_path)
        admit(previous_path, sha(previous_path))
        for name, expected in previous['checks'].items():
            if name not in {str(fixture), str(Path(__file__).resolve())}:
                admit(name, expected)
        fresh = previous['freshProduction']
        save(out / 'reused-port.json', dict(receipt=str(previous_path), receiptSHA256=sha(previous_path)))
    else:
        generated = []
        for path in selected:
            fresh[str(path)] = sha(path)
            target = out / 'generated' / path.name
            target.parent.mkdir(exist_ok=True)
            target.write_text(header + path.read_text())
            admit(target, sha(target))
            generated.append(str(target))
        tripwire = next(Path(name) for name in base_port_command if name.endswith('UnselectedOverlapTripwire.swift'))
        assert str(tripwire) in checks
        generated.append(str(tripwire))
        command = flags + ['-emit-library', '-static', '-emit-module', '-module-name', 'DraftZeroRuledPort',
            *generated, '-emit-module-path', str(out / 'DraftZeroRuledPort.swiftmodule'),
            '-o', str(out / 'libDraftZeroRuledPort.a')]
        save(out / 'compile-port.json', command)
        print(args.lane, 'selected consumer bodies', len(selected), 'lower L2-L6 bodies rebuilt', 0, flush=True)
        recheck()
        execute('compile-port', command, compile_wall, compile_cpu)
        for name in ['DraftZeroRuledPort.swiftmodule', 'libDraftZeroRuledPort.a']:
            admit(out / name, sha(out / name))
        recheck()
        save(out / 'port-receipt.json', dict(state='current-consumer-port-compile-admitted', checks=checks,
            freshProduction=fresh, runs=runs, sourceDIReceipt=str(derivative_path), sourceDIReceiptSHA256=sha(derivative_path),
            lowerAlgebraCommand=str(ordinary / 'command.json'), rebuiltLowerBodies=0))
        admit(out / 'port-receipt.json', sha(out / 'port-receipt.json'))
    proof_header = header + '@testable import DraftZeroRuledPort\n'
    proof_header += '\n'.join(declarations(selected, 'DraftZeroRuledPort')) + '\n'
    probe = out / 'Proof.swift'
    probe.write_text(proof_header + fixture.read_text())
    admit(probe, sha(probe))
    shape = root / 'Tests/OriginalDerivativeLiftHostVerification/Shape.swift'
    admit(shape, sha(shape))
    atlas = root / 'Tests/OriginalPolylineAtlasLiftVerification/Proof.swift'
    polyline = root / 'Tests/OriginalPolylineSurfaceLiftVerification/Proof.swift'
    for path in [atlas, polyline]:
        admit(path, sha(path))
    shape_body = atlas.read_text().split('    nonisolated static func shape(', 1)[1].split('    nonisolated static func prepared', 1)[0]
    points_body = polyline.read_text().split('    nonisolated static func points(', 1)[1].split('    nonisolated static func shape', 1)[0]
    regression = out / 'RegressionShape.swift'
    regression.write_text('import CADCore\n@testable import CADGeometry\n'
        + 'struct PolylineAtlasLiftProof {\n    typealias Admission = DraftZeroRuledAcceptance.Admission\n'
        + '    nonisolated static func shape(' + shape_body + '}\nstruct PolylineLiftProof {\n'
        + '    nonisolated static func points(' + points_body + '}\n')
    admit(regression, sha(regression))
    # Link only the admitted lower source/DI and L2-L6 archives, plus current consumers.
    archives = [name for name in base_proof if name.endswith('.a') and not any(
        name.endswith(excluded) for excluded in ['libPublicLiftPlanePort.a', 'libPolylineLiftAdapters.a'])]
    archives += [str(derivative_module / name) for name in ['libRetainedHostAdapters.a', 'libDerivativePayloadAccess.a']]
    archives = list(dict.fromkeys(archives))
    assert all(name in checks for name in archives)
    product = out / ('Proof.wasm' if portable else 'Proof')
    proof_flags = base_proof[:base_proof.index('-emit-executable')]
    proof_flags = [flag for flag in proof_flags if flag not in {'-DPUBLIC_PROOF_SUBNORMAL', '-DPUBLIC_PROOF_CONTAINED_ALL', '-DPUBLIC_PROOF_ALL_MODES'}]
    proof_flags[1:1] = ['-I', str(port), '-I', str(derivative_module)]
    for index, flag in enumerate(proof_flags):
        if flag == '-num-threads':
            proof_flags[index + 1] = '2'
    link_flags = []
    for index in range(base_proof.index('-emit-executable') + 1, len(base_proof)):
        if base_proof[index] in {'-Xlinker', '-Xclang-linker'}:
            link_flags += base_proof[index:index + 2]
    command = proof_flags + link_flags + ['-emit-executable', str(probe), str(shape), str(regression),
        str(port / 'libDraftZeroRuledPort.a'), *archives, '-o', str(product)]
    save(out / 'compile-proof.json', command)
    recheck()
    execute('compile-proof', command, compile_wall, compile_cpu)
    admit(product, sha(product))
    recheck()
    save(out / 'build-receipt.json', dict(checks=checks, freshProduction=fresh, fixtureSHA256=sha(fixture), runs=runs))
product = build / ('Proof.wasm' if portable else 'Proof')
runtime = [str(product)]
if portable:
    runner = root / 'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'
    node = '/usr/local/bin/node'
    for path in [runner, node]:
        admit(path, sha(path))
    runtime = [node, str(runner), str(product)]
groups = ['ordinary', 'regressions', 'selections', 'guards', 'query-work', 'query-storage', 'depth',
    'cancel-entry', 'cancel-callbacks', 'cancel-final', 'cancel-empty', 'lifetime']
selected_groups = groups if args.groups == 'all' else args.groups.split(',')
assert all(group in groups for group in selected_groups)
recheck()
save(out / 'admission.json', dict(checks=checks, freshProduction=fresh, historicalSources=historical,
    sourceDIReceipt=str(derivative_path), sourceDIReceiptSHA256=sha(derivative_path),
    lowerAlgebraReceipt=str(prior_path), lowerAlgebraReceiptSHA256=sha(prior_path)))
for group in selected_groups:
    execute(group, runtime + [group], 120, 120, allow_failure=args.diagnostic)
    recheck()
save(out / 'receipt.json', dict(success=not args.diagnostic, diagnostic=args.diagnostic, cellComplete=False, lane=args.lane, groups=selected_groups, checks=checks,
    freshProduction=fresh, runs=runs, sourceDIReceipt=str(derivative_path), sourceDIReceiptSHA256=sha(derivative_path),
    lowerAlgebraReceipt=str(prior_path), lowerAlgebraReceiptSHA256=sha(prior_path), historicalSources=historical,
    scope='Current finite original line/zero-draft source and ordinary/callback bare/rich consumers; unchanged source/DI contracts and L2-L6 products reused.'))
