#!/usr/bin/env python3
"""Observe the actual zero-draft ordinary rich fallback using admitted Native products."""
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
save('premises-before.json', dict(head=head, fixtureSHA256=sha(root / 'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledStop.swift'), runnerSHA256=sha(__file__)))
ordinary = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-01-ordinary/native'
parent = read(ordinary / 'receipt.json')
admit(ordinary / 'receipt.json', sha(ordinary / 'receipt.json'))
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
        supplied = Path(snapshots[name]['path'] if name in snapshots else name)
        if name.endswith('/NativeExactRelations/DefaultOriginalLiftPlaneRelationResolver.swift') and sha(supplied) != expected:
            # This delivered derivative consumer is not selected by the line/draft input.
            # Recover only the old admitted bytes, rather than equating new production.
            content = subprocess.check_output(['git', 'show', '99d61ff1:' + str(supplied.relative_to(root))], cwd=root)
            assert hashlib.sha256(content).hexdigest() == expected
            supplied = out / 'historical-source/DefaultOriginalLiftPlaneRelationResolver.swift'
            supplied.parent.mkdir(parents=True, exist_ok=True)
            supplied.write_bytes(content)
        admit(supplied, expected)
for name, expected in lower['product'].items():
    admit(name, expected)
for name, expected in lower['logs'].items():
    admit(Path(parent['parentReceipt']).parent / name, expected)
retained_products = read(ordinary / 'products.json')
for name, expected in retained_products.items():
    admit(name, expected)

# The selected zero-draft constructor/differential fallback is unchanged in the admitted cache.
# The current facade is compiled below; the old cached result DTO is deliberately
# retained only for observing an operation before publication or numerical success.
cache_receipt = root / 'Tests/OriginalDomainConsumerVerification/Evidence/M6/receipt.json'
admit(cache_receipt, lower['inputs'][str(cache_receipt)])
cached = read(cache_receipt)['source_sha256']
selected, differences = [], {}
excluded = {
    'DefaultSurfaceSurfaceIntersector.swift': 'No SSI entry is called.',
    'RationalBivariateAlgebra/GeometryExactScalarFailure.swift': 'Current admitted PublicLiftPlane wrapper.',
    'NativeSurfaceSurfacePointRelations/SurfaceSurfaceIntersectionResult.swift': 'Cached DTO; native guards return nil; rich result construction follows bare return.',
    'PlanePlaneSurfaceIntersector.swift': 'Line/originalDrafted CS does not enter SSI or plane-plane.',
    'DefaultCurveSurfaceIntersector.swift': 'Fresh unchanged current production body compiled below.',
    'CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift': 'Cached DTO explicitly retained for numerical diagnostic; newer issued fields not observed through its ABI.',
    'CurveSurfaceOverlap/DefaultCurveSurfaceIntersector+Overlap.swift': 'Fresh unchanged current production rich body compiled below.',
    'NativeExactGeometricRelations/NativeExactGeometricRelationFailure.swift': 'All exact CS selectors reject line/originalDrafted at their initial guards; actual real fallback is compiled.',
    'NativeExactGeometricRelations/NativeExactGeometryPublicationFailure.swift': 'All exact CS selectors reject line/originalDrafted at their initial guards; actual real fallback is compiled.',
    'OriginalCoons/BoundaryCorrection/OriginalBoundaryCorrectedRationalAtlas.swift': 'No boundary-corrected source is constructed or queried.',
    'OriginalCoons/OriginalCoonsRationalDifferentialAtlas.swift': 'Original drafted wall does not query Coons differential/rational atlas.',
    'OriginalCoons/OriginalSplineTraversalPolynomialPiece.swift': 'Native directed generator interval Taylor traversal does not extract a spline homogeneous atlas.',
    'OriginalCoons/PlaneDerivatives/OriginalPlaneDerivativeSurface3D.swift': 'No originalPlaneDerivative source.',
    'OriginalHigherCurveJets/OriginalParameterCurveHigherTaylor.swift': 'The generator is a native BSpline Curve3D, not a surface parameter curve.',
    'OriginalSourceIssuance/DefaultOriginalFiniteBSplineChartPreparer.swift': 'No original source snapshot issuance or graph-family preparation.',
    'OriginalSourceIssuance/DefaultOriginalSpatialChartIssuer.swift': 'No original source snapshot issuance or graph-family preparation.',
    'RationalBivariateAlgebra/ExactGeometricRelation/ExactGeometricEvidenceKind.swift': 'No exact graph/geometric-relation publication.',
    'RationalBivariateAlgebra/ExactRealCell/ExactRealCellDomain+Specialization.swift': 'No exact graph/geometric-relation decomposition.',
    'RationalBivariateAlgebra/OriginalEuclideanPolylineParameterLaw.swift': 'The generator is native BSpline, not originalPolyline.',
    'RollingBall/RollingBallBlendSurface3D.swift': 'No rollingBall source.',
    'SurfaceSilhouette/OriginalProceduralSurfaceHigherTaylor.swift': 'Prepared originalDrafted intervalJet has its own direct retained-wall branch.',
    'SurfaceSilhouette/OriginalRevolutionSurfaceHigherTaylor.swift': 'No revolution source.',
    'SurfaceSilhouette/OriginalSurfaceHigherJetProvider.swift': 'Prepared originalDrafted intervalJet has its own direct retained-wall branch; generic higher provider is not selected.',
}
excluded_groups = {
    'NativeExactRelations/': 'All exact CS selectors reject line/originalDrafted at their initial guards; actual real fallback is compiled.',
    'OriginalBoundaryClipping/': 'No boundary clipping query.',
    'OriginalDomainIdentity/': 'No original identity or DI query.',
    'OriginalSurfaceEmbedding/': 'No embedding/self-contact query.',
}
for name in cached:
    if not name.startswith(('Sources/CADCore/', 'Sources/CADGeometry/')):
        continue
    current = sha(root / name)
    if current == cached[name]:
        admit(root / name, cached[name])
        selected.append(name)
        continue
    relative = name.removeprefix('Sources/CADGeometry/')
    reason = excluded.get(relative)
    if reason is None:
        reason = next((value for prefix, value in excluded_groups.items() if relative.startswith(prefix)), None)
    if reason is None:
        raise RuntimeError('Unclassified cache source difference: ' + name)
    differences[name] = dict(cachedSHA256=cached[name], currentSHA256=current, exclusion=reason)

command = read(ordinary / 'compile-ordinary.json')
flags = command[:command.index('-emit-executable')]
flags[1:1] = ['-I', str(Path(next(name for name in retained_products if name.endswith('/PublicLiftPlane.swiftmodule'))).parent)]
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
assert flags[flags.index('-target') + 1] == 'arm64-apple-macos15.0'
for path in [flags[0], str(Path(flags[0]).with_name('swift-frontend'))]:
    admit(path, sha(path))
sdk = Path(flags[flags.index('-sdk') + 1])
admit(sdk / 'SDKSettings.json', sha(sdk / 'SDKSettings.json'))

# The current lift selector is admitted independently; only its real nil can
# cross the diagnostic boundary to the cached numerical result ABI.
port_receipt = root / '.build/cs-derivative-lift-plane-native-20261011-v10/receipt.json'
current_port = read(port_receipt)
assert current_port['success']
admit(port_receipt, sha(port_receipt))
for name, expected in current_port['checks'].items():
    admit(name, expected)
for name, expected in current_port['freshProduction'].items():
    admit(name, expected)
port = Path(next(name for name in current_port['checks'] if name.endswith('DerivativeLiftPlanePort.swiftmodule'))).parent
flags[1:1] = ['-I', str(port)]
assert '-j2' in flags
if '-num-threads' in flags:
    flags[flags.index('-num-threads') + 1] = '2'
else:
    flags += ['-num-threads', '2']
prefix = ('import CADCore\n@testable import CADGeometry\n@testable import DerivativeLiftPlanePort\n'
    'import enum DerivativeLiftPlanePort.GeometryExactScalarFailure\n'
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
    admit(target, sha(target)); sources.append(str(target))
adapter = out / 'ActualLiftDeclineAdapter.swift'
adapter.write_text('''import CADCore
@testable import CADGeometry
@testable import DerivativeLiftPlanePort
import struct CADGeometry.CurveSurfaceIntersectionResult

/// No successful result or receipt crosses this diagnostic namespace boundary.
struct OriginalRetainedLiftPlanePublicProducer {
    enum AssemblyFailure: Error { case selectedResultRequiresCurrentDTO }
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false) throws -> CADGeometry.CurveSurfaceIntersectionResult? {
        let actual = try DerivativeLiftPlanePort.OriginalRetainedLiftPlanePublicProducer().resolve(
            curve: curve, surface: surface, options: options, tolerance: tolerance,
            invocation: invocation, retainingRelations: retainingRelations)
        guard actual == nil else {
            print("ASSEMBLY_STOP selected lift result requires its current DTO; no conversion performed")
            throw AssemblyFailure.selectedResultRequiresCurrentDTO
        }
        print("SELECTED_PRODUCER_DECLINED actual current producer returned nil")
        return nil
    }
}
''')
admit(adapter, sha(adapter)); sources.append(str(adapter))
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledStop.swift'
admit(fixture, sha(fixture)); admit(__file__, sha(__file__))
(out / 'Probe.swift').write_bytes(fixture.read_bytes()); admit(out / 'Probe.swift', sha(fixture))
(out / 'driver.py').write_bytes(Path(__file__).read_bytes()); admit(out / 'driver.py', sha(__file__))
archives = [name for name in command if name.endswith('.a') and not name.endswith('libPublicLiftPlanePort.a')]
for index,name in enumerate(archives):
    if name not in checks:
        matches = [path for path, expected in retained_products.items()
            if Path(path).name == Path(name).name and expected == sha(name)]
        assert len(matches) == 1, name
        archives[index] = matches[0]
archives.append(str(port / 'libDerivativeLiftPlanePort.a'))
derivative_command = read(port_receipt.parent / 'compile-proof.json')
archives += [name for name in derivative_command if name.endswith(('/libRetainedHostAdapters.a', '/libDerivativePayloadAccess.a'))]
assert len(archives) == len(set(archives))
assert all(name in checks for name in archives)
product = out / 'DraftZeroRuledStop'
compile_command = flags + ['-module-cache-path', str(out / 'module-cache'), '-emit-executable',
    '-module-name', 'DraftZeroRuledObservation', *sources, str(out / 'Probe.swift'), *archives, '-o', str(product)]
save('compile-command.json', compile_command)
admit(out / 'compile-command.json', sha(out / 'compile-command.json'))
save('admission.json', dict(headBefore=head, checks=checks, freshProduction=fresh,
    selectedUnchangedCacheSources=selected, cacheSourceDifferences=differences,
    currentLiftPortReceipt=str(port_receipt), currentLiftPortSHA256=sha(port_receipt),
    adapter='Actual current admitted selector executes; only real nil crosses; nonnil throws ASSEMBLY_STOP without DTO or receipt conversion.',
    resultDTOScope='Cached numerical DTO exposes six older proof fields; newest three issued fields are not ABI-observed.',
    oracle='T=0,U=2/3,V=1/2,originalGenerator=1/3,XYZ=(1/2,0,2),one incident,image/fiber0'))

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
        admit(product, sha(product)); recheck()
        save('runtime-admission.json', dict(checks=checks, freshProduction=fresh))
        code, log = execute('observation', [str(product)])
        if code != 0: state = 'process-failure-or-timeout'
        elif 'ASSEMBLY_STOP' in log: state = 'explicit-adapter-assembly-stop'
        elif 'OBSERVED_TYPED_PUBLIC_FAILURE' in log: state = 'observed-typed-public-failure'
        elif 'ORDINARY_RICH_RETURNED' in log: state = 'observed-numerical-public-result'
        else: state = 'constructor-or-other-observed-failure'
finally:
    recheck()
    save('receipt.json', dict(cell='CS-DRAFT-ZERO-RULED-01', state=state, cellComplete=False,
        headBefore=head, checks=checks, freshProduction=fresh, postHashesMatch=True, runs=runs,
        logs={p.name:sha(p) for p in out.glob('*.log')},
        scope='One admitted current-facade/real cached fallback diagnostic; no current whole-package or exact cell acceptance.'))
print('OBSERVATION', state, flush=True)
