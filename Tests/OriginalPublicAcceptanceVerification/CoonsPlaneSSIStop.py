#!/usr/bin/env python3
"""Observe one ordinary SSI input with two fresh facade bodies and admitted products."""
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
parser.add_argument('--resolve-plane-contract', action='store_true')
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


def execute(label, command):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
    started = time.monotonic()
    log = out / (label + '.log')
    with log.open('w') as stream:
        process = subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True, preexec_fn=constrain)
        try:
            code = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            children = descendants(process.pid)
            for pid in reversed(children):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            code = 'timeout'
    runs.append(dict(label=label, command=command, exitCode=code, wallLimitSeconds=120,
                     cpuLimitSeconds=120, elapsedSeconds=time.monotonic() - started,
                     logSHA256=sha(log)))
    save('runs.json', runs)
    print(label, code, round(runs[-1]['elapsedSeconds'], 3), flush=True)
    return code, log.read_text()


head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True, timeout=120).strip()
save('premises-before.json', dict(head=head, fixtureSHA256=sha(root / 'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIStop.swift'), runnerSHA256=sha(__file__)))
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
        admit(snapshots[name]['path'] if name in snapshots else name, expected)
for name, expected in lower['product'].items():
    admit(name, expected)
for name, expected in lower['logs'].items():
    admit(Path(parent['parentReceipt']).parent / name, expected)
retained_products = read(ordinary / 'products.json')
for name, expected in retained_products.items():
    admit(name, expected)

# The source graph of this Coons/plane fallback is unchanged in the admitted cache.
# The current facade is compiled below; the old cached result DTO is deliberately
# retained only for observing an operation before publication or numerical success.
cache_receipt = root / 'Tests/OriginalDomainConsumerVerification/Evidence/M6/receipt.json'
admit(cache_receipt, lower['inputs'][str(cache_receipt)])
cached = read(cache_receipt)['source_sha256']
selected, differences = [], {}
resolution = None
if args.resolve_plane_contract:
    previous = root / '.build/ssi-coons-plane-01-observation-20261011-native-admitted/receipt.json'
    admit(previous, '1c972106bd6ff7ee96e72bf4ebdffe56582a1a8609a026690a1035f5b03c877f')
    previous_receipt = read(previous)
    admit(previous.parent / 'admission.json', previous_receipt['admissionSHA256'])
    for name, expected in previous_receipt['logs'].items():
        admit(previous.parent / name, expected)
    plane_evidence = root / 'Tests/OriginalPlanePlaneIntersectionVerification/Evidence/native'
    plane_receipt = plane_evidence / 'receipt.json'
    admit(plane_receipt, sha(plane_receipt))
    plane = read(plane_receipt)
    for name, expected in plane['inputs'].items():
        admit(root / name, expected)
    for name, expected in plane['currentCachedSourcePremises'].items():
        admit(root / name, expected)
        if cached.get(name) != expected:
            raise RuntimeError('Plane contract field dependency differs from admitted cache: ' + name)
    admit(root / 'Tests/OriginalPlanePlaneIntersectionVerification/Verify.py', plane['driverSHA256'])
    admit(root / 'Tests/LegacyPlaneTorusCleanup/receipt.json', plane['dependencyReceiptSHA256'])
    admit(root / 'Tests/OriginalDomainConsumerVerification/Evidence/M2/receipt.json', plane['sourceGenerationReceiptSHA256'])
    admit(plane_evidence / 'runtime.log', plane['runtimeSHA256'])
    plane_product = Path(plane['command'][plane['command'].index('-o') + 1])
    if plane_product.exists():
        admit(plane_product, plane['productSHA256'])
    resolution = dict(previousReceipt=str(previous), previousSHA256=sha(previous),
        planeReceipt=str(plane_receipt), planeReceiptSHA256=sha(plane_receipt),
        productNamespace='Existing PPFIX product is a Proof executable without an emitted importable module; not linked.',
        addedSource='Sources/CADGeometry/PlanePlaneSurfaceIntersector.swift',
        fieldPremiseCount=len(plane['currentCachedSourcePremises']),
        existingPPFIXCasesRerun=False)
# These changed cache bodies belong to branches not entered by the direct
# original-Coons/plane numeric fallback. The facade and scalar publication
# wrapper are supplied by fresh/current admitted bodies instead. The result DTO
# remains an explicit limitation, never an issued-receipt acceptance premise.
excluded = {
    'DefaultSurfaceSurfaceIntersector.swift': 'Fresh current facade below.',
    'RationalBivariateAlgebra/GeometryExactScalarFailure.swift': 'Current admitted PublicLiftPlane wrapper.',
    'NativeSurfaceSurfacePointRelations/SurfaceSurfaceIntersectionResult.swift': 'Cached DTO; native guards return nil; rich result construction follows bare return.',
    'PlanePlaneSurfaceIntersector.swift': 'Fresh current real body for the observed options-signature gap.' if args.resolve_plane_contract else 'First canonical surface is unsupported, not plane.',
    'DefaultCurveSurfaceIntersector.swift': 'SSI input selects no CS dispatcher.',
    'CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift': 'SSI input selects no CS result.',
    'CurveSurfaceOverlap/DefaultCurveSurfaceIntersector+Overlap.swift': 'SSI input selects no CS overlap.',
    'NativeExactGeometricRelations/NativeExactGeometricRelationFailure.swift': 'All native SSI producers reject procedural first input at their initial guards.',
    'NativeExactGeometricRelations/NativeExactGeometryPublicationFailure.swift': 'All native SSI producers reject procedural first input at their initial guards.',
    'OriginalCoons/BoundaryCorrection/OriginalBoundaryCorrectedRationalAtlas.swift': 'No boundary-corrected source is constructed or queried.',
    'OriginalCoons/OriginalCoonsRationalDifferentialAtlas.swift': 'Direct Coons intervalJet uses retained boundaries, not rational embedding atlas.',
    'OriginalCoons/OriginalSplineTraversalPolynomialPiece.swift': 'No homogeneous/differential atlas or guide chain is queried.',
    'OriginalCoons/PlaneDerivatives/OriginalPlaneDerivativeSurface3D.swift': 'No originalPlaneDerivative source.',
    'OriginalHigherCurveJets/OriginalParameterCurveHigherTaylor.swift': 'All four boundaries are bSpline Curve3D, not parameter curves.',
    'OriginalSourceIssuance/DefaultOriginalFiniteBSplineChartPreparer.swift': 'No original source snapshot issuance or graph-family preparation.',
    'OriginalSourceIssuance/DefaultOriginalSpatialChartIssuer.swift': 'No original source snapshot issuance or graph-family preparation.',
    'RationalBivariateAlgebra/ExactGeometricRelation/ExactGeometricEvidenceKind.swift': 'No exact graph/geometric-relation publication.',
    'RationalBivariateAlgebra/ExactRealCell/ExactRealCellDomain+Specialization.swift': 'No exact graph/geometric-relation decomposition.',
    'RationalBivariateAlgebra/OriginalEuclideanPolylineParameterLaw.swift': 'All four boundaries are bSpline, not originalPolyline.',
    'RollingBall/RollingBallBlendSurface3D.swift': 'No rollingBall source.',
    'SurfaceSilhouette/OriginalProceduralSurfaceHigherTaylor.swift': 'Prepared Coons intervalJet has its own direct branch.',
    'SurfaceSilhouette/OriginalRevolutionSurfaceHigherTaylor.swift': 'No revolution source.',
    'SurfaceSilhouette/OriginalSurfaceHigherJetProvider.swift': 'Prepared Coons intervalJet has its own direct branch; generic higher provider is offset only.',
}
excluded_groups = {
    'NativeExactRelations/': 'All native SSI producers reject procedural first input at their initial guards.',
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
if args.resolve_plane_contract:
    admit(flags[0], plane['compilerSHA256'])
    admit(sdk / 'SDKSettings.json', plane['sdkSettingsSHA256'])
prefix = 'import CADCore\n@testable import CADGeometry\n@testable import PublicLiftPlane\nimport enum PublicLiftPlane.GeometryExactScalarFailure\n'
sources = []
facades = ['DefaultSurfaceSurfaceIntersector.swift', 'DefaultSurfaceSurfaceIntersector+Result.swift']
if args.resolve_plane_contract:
    facades.append('PlanePlaneSurfaceIntersector.swift')
for name in facades:
    source = root / 'Sources/CADGeometry' / name
    fresh[str(source)] = sha(source)
    generated = out / name
    generated.write_text(prefix + source.read_text())
    admit(generated, sha(generated))
    sources.append(str(generated))
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIStop.swift'
admit(fixture, sha(fixture))
admit(__file__, sha(__file__))
support = [name for name in command if name.endswith('.swift') and Path(name).name in {'Fixture0.swift', 'Fixture1.swift'}]
for name in support:
    admit(name, snapshots[name]['sha256'])
archives = [name for name in command if name.endswith('.a') and not name.endswith('libPublicLiftPlanePort.a')]
for index, name in enumerate(archives):
    if name not in checks:
        candidates = [retained for retained, expected in retained_products.items()
            if Path(retained).name == Path(name).name and expected == sha(name)]
        if len(candidates) != 1:
            raise RuntimeError('Unadmitted archive: ' + name)
        archives[index] = candidates[0]
save('admission.json', dict(headBefore=head, checks=checks, freshProduction=fresh,
    selectedUnchangedCacheSources=selected, cacheSourceDifferences=differences, excludedUnselectedCSInputs=sorted(unused),
    causalAssemblyResolution=resolution,
    resultDTOScope='Cached numerical result DTO; current issued-receipt field publication is not verified.',
    oracle='XYZ=(1/2,V,0), CoonsUV=(1/2,V), planeUV=(0,-V), V in closed [0,1]; image 1, fiber 0; all closed chart incidents.'))
version_code, version = execute('compiler-version', [flags[0], '--version'])
assert version_code == 0 and 'Swift version 6.4' in version
flags += ['-module-cache-path', str(out / 'module-cache')]
product = out / 'CoonsPlaneSSIStop'
code, log = execute('compile-link', flags + ['-emit-executable', '-module-name', 'CoonsPlaneSSIObservation',
    *sources, str(fixture), *support, *archives, '-o', str(product)])
outcome = 'assembly-unavailable'
if code == 0:
    admit(product, sha(product))
    for name, expected in checks.items():
        admit(name, expected)
    for mode in ['bare', 'rich']:
        code, log = execute('runtime-' + mode, [str(product), mode])
        if code != 0:
            outcome = 'process-failure-or-timeout'
            break
        if 'OBSERVED_TYPED_FAILURE' in log or 'OBSERVED_OTHER_FAILURE' in log:
            outcome = 'observed-public-failure'
            break
        if 'NUMERICAL_SUCCESS' not in log:
            outcome = 'missing-observation'
            break
        outcome = 'numerical-success-only'
post = {name: sha(name) for name in checks}
fresh_post = {name: sha(name) for name in fresh}
head_after = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True, timeout=120).strip()
save('receipt.json', dict(cell='SSI-COONS-PLANE-01', outcome=outcome, headBefore=head, headAfter=head_after,
    parentReceipt=str(ordinary / 'receipt.json'), parentSHA256=sha(ordinary / 'receipt.json'),
    admissionSHA256=sha(out / 'admission.json'), checks=checks, freshProduction=fresh,
    postHashesMatch=post == checks, freshProductionPostHashesMatch=fresh_post == fresh,
    products={str(product): sha(product)} if product.exists() else {}, runs=runs,
    logs={p.name: sha(p) for p in out.glob('*.log')},
    causalAssemblyResolution=resolution,
    scope='One ordinary original Coons/whole-plane SSI observation; no repair, no exact coverage acceptance, no lower or broad rebuild.'))
print('OBSERVATION', outcome, flush=True)
if code != 0:
    print(log[-12000:])
