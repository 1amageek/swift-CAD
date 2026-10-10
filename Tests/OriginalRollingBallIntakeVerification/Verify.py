#!/usr/bin/env python3
"""Verify the actual rolling-ball producer without a broad CAD build."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.output.resolve()
work.mkdir(parents=True, exist_ok=False)
portable = args.lane in {'wasm', 'embedded'}
receipt_path = root / 'Tests/OriginalDomainConsumerVerification/Evidence/M6' / (
    args.lane + '/receipt.json' if portable else 'receipt.json')
receipt = json.loads(receipt_path.read_text())
cache_root = Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-' + (
    args.lane if portable else 'native') + '-production')
cache = cache_root / ('wasm32-unknown-wasip1/debug' if portable else 'out/Products/Debug')
swift = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc')
records = []
(work / 'driver.py').write_bytes(Path(__file__).read_bytes())
inputs = {}
products = {}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def admit(path, expected, destination):
    path = Path(path)
    if digest(path) != expected:
        raise RuntimeError('Changed verification premise: ' + str(path))
    destination[str(path)] = expected


def execute(label, command):
    start = time.monotonic()
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120)
    (work / (label + '.log')).write_text(result.stdout + result.stderr)
    records.append(dict(label=label, command=list(map(str, command)), timeoutSeconds=120,
                        elapsedSeconds=time.monotonic()-start, exitCode=result.returncode))
    (work / 'runs.json').write_text(json.dumps(records, indent=2)+'\n')
    print(label, result.returncode, round(records[-1]['elapsedSeconds'], 3), flush=True)
    if result.returncode:
        print(result.stderr[-9000:])
        raise SystemExit(result.returncode)


# Import the real unchanged constructor children, exact coefficient algebra and
# public numerical evaluator dependencies. Recompile the changed producer bodies.
source_names = [
    'RollingBall/RollingBallBlendSurface3D.swift',
    'RollingBall/RollingBallBlendSurface3D+Enclosure.swift',
    'DefaultSurfaceRegularityValidator.swift',
    'StrictDecoding.swift',
]
source_names += ['OriginalSourceIssuance/' + name + '.swift' for name in [
    'OriginalRollingBallGraphProducer', 'OriginalRollingBallSourceReading', 'OriginalRollingBallSnapshot',
    'OriginalRollingBallSnapshotProvider', 'OriginalRollingBallGraphEvidence',
    'OriginalFiniteNativeRollingBallGraphs', 'OriginalFiniteNativeRollingBallGraphPreparing',
    'DefaultOriginalFiniteNativeRollingBallGraphPreparer',
    'OriginalParametricVariableLayout', 'OriginalParametricGraphCondition', 'OriginalParametricGraphReceipt',
]]
source_names += ['OriginalDomainIdentity/OriginalDomainCoverage/' + name + '.swift' for name in [
    'OriginalParametricGraphDomainBinding', 'OriginalDomainBoundParametricGraph',
    'DefaultOriginalParametricGraphDomainBinder',
    'OriginalNativeRollingBallDomainIssuing', 'OriginalNativeRollingBallDomainCover',
    'DefaultOriginalNativeRollingBallDomainIssuer',
]]
sources = [root / 'Sources/CADGeometry' / name for name in source_names]
recompiled = {str(path.relative_to(root)) for path in sources}
# These unrelated equality/publication/identity paths are never invoked by this
# position/source/DI proof. Their old cached bodies are not verification evidence.
unselected = {
    'OriginalCoons/OriginalCoonsRationalDifferentialAtlas.swift',
    'OriginalCoons/BoundaryCorrection/OriginalBoundaryCorrectedRationalAtlas.swift',
    'OriginalCoons/PlaneDerivatives/OriginalPlaneDerivativeSurface3D.swift',
    'CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift', 'DefaultSurfaceSurfaceIntersector.swift',
    'NativeExactGeometricRelations/NativeExactGeometricRelationFailure.swift',
    'NativeExactGeometricRelations/NativeExactGeometryPublicationFailure.swift',
    'NativeSurfaceSurfacePointRelations/SurfaceSurfaceIntersectionResult.swift',
    'OriginalDomainIdentity/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift',
    'OriginalDomainIdentity/OriginalParameterIdentity/OriginalParameterIdentity.swift',
    'PlanePlaneSurfaceIntersector.swift', 'RationalBivariateAlgebra/ExactGeometricRelation/ExactGeometricEvidenceKind.swift',
    'RationalBivariateAlgebra/ExactRealCell/ExactRealCellDomain+Specialization.swift',
    'RationalBivariateAlgebra/GeometryExactScalarFailure.swift',
}
# Field-query overloads were added after the cache; original same-field operations
# used by this proof have unchanged bodies. The accepted M6 receipts own the new ports.
additive_queries = {
    'OriginalDomainIdentity/ExactParameterDomain/ExactParameterDomain+Queries.swift',
    'OriginalDomainIdentity/OriginalParameterTransport/OriginalParameterSelection+Operations.swift',
}
skipped = {}
for name, expected in receipt['source_sha256'].items():
    if not name.startswith(('Sources/CADCore/', 'Sources/CADGeometry/')):
        continue
    relative = name.removeprefix('Sources/CADGeometry/')
    if name in recompiled or relative in unselected or relative in additive_queries or relative.startswith((
        'NativeExactRelations/', 'OriginalBoundaryClipping/', 'OriginalSurfaceEmbedding/')):
        skipped[name] = expected
        continue
    admit(root / name, expected, inputs)

modules = ['CADCore', 'CADGeometry', 'HashTreeCollections', 'InternalCollectionsUtilities']
objects = {module: [] for module in modules}
for name, expected in receipt['products'].items():
    path = cache_root / name
    if path.suffix == '.swiftmodule' and (path.stem in modules or path.parent.name in {module + '.swiftmodule' for module in modules}):
        admit(path, expected, products)
    if path.suffix == '.o':
        for module in modules:
            if path.parent.name == module + '.build' or path.stem == module:
                admit(path, expected, products)
                objects[module].append(path)
for module in modules:
    if not objects[module] or not any((Path(name).stem == module or Path(name).parent.name == module + '.swiftmodule') and Path(name).suffix == '.swiftmodule' for name in products):
        raise RuntimeError('Missing cache module/object receipt: ' + module)
for name, expected in receipt['artifact_sha256'].items():
    admit(cache / (name + '.wasm' if portable else name), expected, products)
for name, expected in receipt['runtime_log_sha256'].items():
    admit(receipt_path.parent / name, expected, products)
inputs[str(receipt_path)] = digest(receipt_path)
inputs[str(Path(__file__).resolve())] = digest(__file__)
inputs[str(swift)] = digest(swift)

common = [swift, '-swift-version', '6', '-package-name', 'nativeexactrelationverification']
if portable:
    sdk_root = Path('/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1')
    sdk_path = sdk_root / ('embedded-swift-sdk.json' if args.lane == 'embedded' else 'swift-sdk.json')
    sdk = json.loads(sdk_path.read_text())['targetTriples']['wasm32-unknown-wasip1']
    toolset_path = sdk_root / sdk['toolsetPaths'][0]
    toolset = json.loads(toolset_path.read_text())
    resources = sdk_root / sdk['swiftResourcesPath']
    common += ['-sdk', sdk_root / sdk['sdkRootPath'], '-target', 'wasm32-unknown-wasip1',
               '-resource-dir', resources, '-tools-directory', sdk_root / toolset['rootPath'],
               *toolset['swiftCompiler']['extraCLIOptions'], '-Xclang-linker', '-resource-dir',
               '-Xclang-linker', resources / 'clang']
    inputs[str(sdk_path)] = digest(sdk_path)
    inputs[str(toolset_path)] = digest(toolset_path)
else:
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    common += ['-sdk', sdk, '-target', 'arm64-apple-macos15.0']
    if args.lane == 'asan':
        common += ['-sanitize=address', '-Xlinker', '-dead_strip']
if args.lane == 'embedded':
    common += ['-enable-experimental-feature', 'Embedded', '-whole-module-optimization', '-Onone']
common += ['-I', cache / 'Modules' if portable else cache, '-I', work]

compiled = []
for path in sources:
    inputs[str(path)] = digest(path)
    destination = work / 'Sources' / path.name
    destination.parent.mkdir(exist_ok=True)
    # Imports are the sole assembly transformation. No producer expression or
    # stored property is replaced; source hashes bind both original and compiled bytes.
    destination.write_text('import CADCore\n@testable import CADGeometry\n' + path.read_text())
    products[str(destination)] = digest(destination)
    compiled.append(destination)
(work / 'inputs.json').write_text(json.dumps(dict(inputs=inputs, cachedProducts=products,
                                                excludedCachedBodies=skipped), indent=2)+'\n')
execute('compile', common + ['-emit-library', '-static', '-emit-module', '-enable-testing',
    '-module-name', 'RollingBallAdapters', *compiled, '-emit-module-path',
    work / 'RollingBallAdapters.swiftmodule', '-o', work / 'libRollingBallAdapters.a'])
archives = []
for module, inventory in objects.items():
    archive = work / ('libCached' + module + '.a')
    execute('archive-'+module, [swift.parent / 'llvm-ar' if portable else 'ar', '-rcs', archive, *inventory])
    archives.append(archive)
proof = root / 'Tests/OriginalRollingBallIntakeVerification/Proof.swift'
inputs[str(proof)] = digest(proof)
link = []
if portable:
    # Match the repository's existing WASI stack configuration, rather than the
    # bare linker default used by the initial diagnostic assembly.
    configuration = root / 'Tests/OriginalDomainConsumerVerification/Scripts/RunConsumer.py'
    inputs[str(configuration)] = digest(configuration)
    if 'stack-size=67108864' not in configuration.read_text():
        raise RuntimeError('Changed authoritative consumer WASI stack configuration')
    link += ['-Xlinker', '-z', '-Xlinker', 'stack-size=67108864']
if args.lane == 'embedded':
    unicode_library = Path(receipt['unicode_data_tables']['path'])
    admit(unicode_library, receipt['unicode_data_tables']['sha256'], products)
    link += ['-Xlinker', '-lc++', '-Xlinker', '-lswift_Concurrency', unicode_library]
artifact = work / ('RollingBallProof.wasm' if portable else 'RollingBallProof')
execute('link', common + ['-parse-as-library', '-D', 'ORIGINAL_ROLLING_BALL_ADAPTER_VERIFICATION',
    proof, work / 'libRollingBallAdapters.a', *archives, *link, '-o', artifact])
if portable:
    node = Path('/usr/local/bin/node')
    runner = root / 'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'
    inputs[str(node)] = digest(node)
    inputs[str(runner)] = digest(runner)
    execute('runtime', [node, runner, artifact])
else:
    execute('runtime', [artifact])
for name, expected in inputs.items():
    admit(name, expected, {})
for name, expected in products.items():
    admit(name, expected, {})
for path in [artifact, work / 'libRollingBallAdapters.a', work / 'RollingBallAdapters.swiftmodule', *archives]:
    products[str(path)] = digest(path)
(work / 'receipt.json').write_text(json.dumps(dict(lane=args.lane, inputs=inputs, products=products,
    commands=records, logs={str(path):digest(path) for path in work.glob('*.log')},
    excludedCachedBodies=skipped, scope='Focused original producer/source/DI execution; no broad CAD build. '
    'Changed source is instrumented for ASAN; cached child objects are not.'), indent=2)+'\n')
print('PASS rolling-ball source/DI receipt', len(inputs), len(products), flush=True)
