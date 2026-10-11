#!/usr/bin/env python3
"""Observe one fixed revolution-axis ordinary rich request using admitted Native products."""
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
checks, fresh, runs = {}, {}, []


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def save(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')


def admit(path, expected):
    path = Path(path)
    if not path.is_file() or sha(path) != expected:
        raise RuntimeError('Receipt premise differs: ' + str(path))
    checks[str(path)] = expected


def descendants(pid):
    tree = {}
    for line in subprocess.check_output(['ps', '-axo', 'pid=,ppid='], text=True, timeout=120).splitlines():
        child, parent = map(int, line.split())
        tree.setdefault(parent, []).append(child)
    pending, found = [pid], []
    while pending:
        children = tree.get(pending.pop(), [])
        found.extend(children)
        pending.extend(children)
    return found


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
    save('runs.json', runs)
    admit(log, run['logSHA256'])
    print(label, process.returncode, round(run['elapsedSeconds'], 3), flush=True)
    assert not remaining, run
    return ('timeout' if timed_out else process.returncode), log.read_text()


head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True, timeout=120).strip()
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/RevolutionAxisFiberObservation.swift'
historical = {}

def admit_prior(name, expected):
    path = Path(name)
    if path.is_file() and sha(path) == expected:
        admit(path, expected)
        return
    relative = path.relative_to(root)
    allowed = {
        'DefaultOriginalIssuedGraphRelationResolver.swift',
        'OriginalIssuedGraphParameterRefinement.swift',
        'OriginalIssuedGraphRelationPair.swift',
        'OriginalIssuedGraphRelations.swift',
    }
    assert relative.name in allowed, name
    content = subprocess.check_output(['git', 'show', 'e9d1c9a8:' + str(relative)], cwd=root, timeout=120)
    assert hashlib.sha256(content).hexdigest() == expected, name
    snapshot = out / 'historical-source' / relative
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    snapshot.write_bytes(content)
    admit(snapshot, expected)
    historical[name] = dict(path=str(snapshot), sha256=expected, commit='e9d1c9a8',
        scope='Historical lower graph input; line/revolution exact selectors decline before graph preparation.')

accepted = root / '.build/cs-draft-zero-ruled-native-20261012-v4'
accepted_receipt = accepted / 'receipt.json'
prior = read(accepted_receipt)
assert prior['success'] and prior['lane'] == 'native'
admit(accepted_receipt, sha(accepted_receipt))
build_path = accepted / 'build-receipt.json'
admit(build_path, sha(build_path))
build = read(build_path)
assert all(run['exitCode'] == 0 for run in build['runs'])
for name, expected in build['checks'].items():
    admit_prior(name, expected)
port = root / '.build/cs-draft-zero-ruled-native-20261011-v2'
port_receipt = port / 'port-receipt.json'
admit(port_receipt, sha(port_receipt))
port_record = read(port_receipt)
assert all(run['exitCode'] == 0 for run in port_record['runs'])
for name, expected in port_record['freshProduction'].items():
    admit_prior(name, expected)
for name in ['DraftZeroRuledPort.swiftmodule', 'libDraftZeroRuledPort.a']:
    product_path = str(port / name)
    admit(product_path, port_record['checks'][product_path])

source_receipts = {}
for relative in ['Tests/OriginalRevolutionSourceVerification/Evidence/receipt.json',
        'Tests/OriginalDomainIdentityVerification/RevolutionDomainEvidence/receipt.json']:
    path = root / relative
    admit(path, sha(path))
    source_receipts[relative] = sha(path)

# The M6 artifact is reused only where its actual selected bodies still match.
cache_receipt = root / 'Tests/OriginalDomainConsumerVerification/Evidence/M6/receipt.json'
admit(cache_receipt, sha(cache_receipt))
cached = read(cache_receipt)['source_sha256']
selected_cache = {}
selected_names = ['BSplineCurve3D.swift', 'OriginalRootSpan/OriginalCurveRootSpan3D.swift',
    'OriginalRevolution/OriginalRevolutionSurface3D.swift', 'Surface3D.swift',
    'PreparedSurfaceDifferentialEncloser.swift']
for relative in selected_names:
    name = 'Sources/CADGeometry/' + relative
    admit(root / name, cached[name])
    selected_cache[name] = cached[name]

# All other compiled lower inputs and artifacts are bound by the admitted build.
# The fresh facade bypasses its deliberately unselected overlap tripwire.
base_command_path = accepted / 'compile-proof.json'
admit(base_command_path, sha(base_command_path))
base_command = read(base_command_path)
flags = base_command[:base_command.index('-emit-executable')]
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
assert flags[flags.index('-target') + 1] == 'arm64-apple-macos15.0'
for path in [flags[0], str(Path(flags[0]).with_name('swift-frontend'))]:
    admit(path, sha(path))
admit(Path(flags[flags.index('-sdk') + 1]) / 'SDKSettings.json',
    sha(Path(flags[flags.index('-sdk') + 1]) / 'SDKSettings.json'))
if '-num-threads' in flags:
    flags[flags.index('-num-threads') + 1] = '2'
else:
    flags += ['-num-threads', '2']
prefix = ('import CADCore\n@testable import CADGeometry\n@testable import DraftZeroRuledPort\n'
    'import enum DraftZeroRuledPort.GeometryExactScalarFailure\n'
    'import struct CADGeometry.CurveSurfaceIntersectionResult\n'
    'import protocol CADGeometry.CurveSurfaceIntersectionResolving\n')
sources = []
for relative in ['DefaultCurveSurfaceIntersector.swift',
        'CurveSurfaceOverlap/DefaultCurveSurfaceIntersector+Overlap.swift',
        'CurveSurfaceOverlap/CurveSurfaceOverlapResolver.swift']:
    path = root / 'Sources/CADGeometry' / relative
    fresh[str(path)] = sha(path)
    target = out / path.name
    target.write_text(prefix + path.read_text())
    admit(target, sha(target))
    sources.append(str(target))

adapter = out / 'ActualSelectorDeclineAdapters.swift'
wrapper = """import CADCore
@testable import CADGeometry
@testable import DraftZeroRuledPort
import struct CADGeometry.CurveSurfaceIntersectionResult

/// No successful result crosses the diagnostic namespace boundary.
struct SELECTOR {
    enum AssemblyFailure: Error { case selectedResultRequiresCurrentDTO }
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false) throws -> CADGeometry.CurveSurfaceIntersectionResult? {
        let actual = try DraftZeroRuledPort.SELECTOR().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation,
            retainingRelations: retainingRelations)
        guard actual == nil else {
            print("ASSEMBLY_STOP SELECTOR returned a current DTO; no conversion performed")
            throw AssemblyFailure.selectedResultRequiresCurrentDTO
        }
        print("SELECTED_PRODUCER_DECLINED SELECTOR actual current producer returned nil")
        return nil
    }
}
"""
adapter.write_text('\n'.join(wrapper.replace('SELECTOR', name) for name in [
    'OriginalDraftedZeroLinePublicProducer', 'OriginalRetainedLiftPlanePublicProducer']))
admit(adapter, sha(adapter))
sources.append(str(adapter))
for path in [fixture, Path(__file__).resolve()]:
    admit(path, sha(path))
(out / 'Probe.swift').write_bytes(fixture.read_bytes())
admit(out / 'Probe.swift', sha(fixture))
(out / 'driver.py').write_bytes(Path(__file__).read_bytes())
admit(out / 'driver.py', sha(__file__))
archives = [name for name in base_command if name.endswith('.a')]
assert len(archives) == len(set(archives))
assert all(name in checks for name in archives)
product = out / 'RevolutionAxisFiberObservation'
compile_command = flags + ['-module-cache-path', str(out / 'module-cache'), '-emit-executable',
    '-module-name', 'RevolutionAxisObservation', *sources, str(out / 'Probe.swift'), *archives, '-o', str(product)]
save('compile-command.json', compile_command)
admit(out / 'compile-command.json', sha(out / 'compile-command.json'))
save('admission.json', dict(headBefore=head, checks=checks, freshProduction=fresh,
    selectedUnchangedCacheSources=selected_cache, historicalSources=historical,
    sourceReceipts=source_receipts, admittedPortReceipt=str(port_receipt),
    admittedPortSHA256=sha(port_receipt),
    adapter='Actual current draft/lift selectors execute; only real nil crosses; nonnil is explicit ASSEMBLY_STOP.',
    resultDTOScope='Cached numerical DTO; newest issued fields are not ABI-observed.',
    oracle='T=0,V=1,allU[-B,B],B=exact binary64 2*Double.pi; image0/fiber1; both intrinsic-label seam incidents at -B,0,B'))

def recheck():
    for name, expected in checks.items():
        assert sha(name) == expected, name
    for name, expected in fresh.items():
        assert sha(name) == expected, name

state = 'assembly-unavailable'
try:
    recheck()
    code, log = execute('compile-link', compile_command)
    if code == 0:
        admit(product, sha(product))
        recheck()
        save('runtime-admission.json', dict(checks=checks, freshProduction=fresh))
        code, log = execute('observation', [str(product)])
        if code != 0: state = 'process-failure-or-timeout'
        elif 'ASSEMBLY_STOP' in log: state = 'explicit-adapter-assembly-stop'
        elif 'OBSERVED_TYPED_PUBLIC_FAILURE' in log: state = 'observed-typed-public-failure'
        elif 'ORDINARY_RICH_RETURNED' in log: state = 'observed-numerical-public-result'
        else: state = 'constructor-or-other-observed-failure'
finally:
    recheck()
    save('receipt.json', dict(cell='CS-REVOLUTION-AXIS-FIBER-01', state=state, cellComplete=False,
        headBefore=head, checks=checks, freshProduction=fresh, historicalSources=historical,
        postHashesMatch=True, runs=runs, logs={p.name:sha(p) for p in out.glob('*.log')},
        scope='One current-facade/real-overlap/native cached evaluation diagnostic; no whole-package or exact cell acceptance.'))
print('OBSERVATION', state, flush=True)
