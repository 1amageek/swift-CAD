#!/usr/bin/env python3
"""Compile only source adapters; reuse validated modules without upper-target builds."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--lane', choices=['native', 'asan', 'wasm', 'embedded'], default='native')
parser.add_argument('--geometry-cache', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
swiftc = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc')
output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
geometry = args.geometry_cache.resolve()
wasm = args.lane in ('wasm', 'embedded')
configuration = 'Debug-webassembly-wasm32' if wasm else 'Debug'
architecture = 'wasm32' if wasm else 'arm64'
gp = geometry / 'out/Products' / configuration
if wasm:
    sdk_base = Path('/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1')
    sdk_description = sdk_base / ('embedded-swift-sdk.json' if args.lane == 'embedded' else 'swift-sdk.json')
    sdk_data = json.loads(sdk_description.read_text())['targetTriples']['wasm32-unknown-wasip1']
    resources = sdk_base / sdk_data['swiftResourcesPath']
    toolset = json.loads((sdk_base / sdk_data['toolsetPaths'][0]).read_text())
    sdk = str(sdk_base / sdk_data['sdkRootPath'])
    common = [str(swiftc), '-sdk', sdk, '-target', 'wasm32-unknown-wasip1',
        '-resource-dir', str(resources), '-tools-directory', str(sdk_base / toolset['rootPath']),
        *toolset['swiftCompiler']['extraCLIOptions'],
        '-Xclang-linker', '-resource-dir', '-Xclang-linker', str(resources / 'clang')]
else:
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    common = [str(swiftc), '-sdk', sdk, '-target', 'arm64-apple-macos15.0']
    if args.lane == 'asan': common += ['-sanitize=address', '-Xlinker', '-dead_strip']
common += ['-swift-version', '6', '-package-name', 'nativeexactrelationverification', '-I', str(gp)]
# Reuse only a cache with an existing runtime receipt for the exact target lane.
receipt_path = root / 'Tests/NativeExactRelationVerification/PublicReviewFixEvidence/receipt.json'
receipt = json.loads(receipt_path.read_text())
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
old_proof = gp / ('NativeExactGeometricProof.wasm' if wasm else 'NativeExactGeometricProof')
expected = receipt['products'][args.lane + '/NativeExactGeometricProof']['sha256']
if digest(old_proof) != expected: raise RuntimeError('Geometry cache does not match its validated runtime artifact')
# These are the existing provider paths used here; solver, closure and L2 changes
# are outside this execution. Record, but do not generalize to, that other scope.
prefixes = ['Sources/CADCore/', 'Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/',
    'Sources/CADGeometry/OriginalAffineOperationWord/', 'Sources/CADGeometry/OriginalAffineImage/',
    'Sources/CADGeometry/PeriodicBSpline/',
    'Sources/CADGeometry/RationalBivariateAlgebra/ExactPolynomial/',
    'Sources/CADGeometry/RationalBivariateAlgebra/ExactRealCell/',
    'Sources/CADGeometry/RationalBivariateAlgebra/ExactParametricRelation/']
exact = ['Sources/CADGeometry/BSplineCurve3D.swift', 'Sources/CADGeometry/BSplineSurface3D.swift',
    'Sources/CADGeometry/AnalyticSurface3D.swift', 'Sources/CADGeometry/AnalyticBasis.swift']
premises = {name: expected_hash for name, expected_hash in receipt['source_sha256'].items()
    if name in exact or any(name.startswith(prefix) for prefix in prefixes)}
for name, expected_hash in premises.items():
    if digest(root / name) != expected_hash:
        raise RuntimeError('Changed cached provider premise: ' + name)
# Import overlays alter module visibility only; production sources are compiled
# verbatim after the import prefix. They share one cached lower nominal identity.
overlay = output / 'overlays'; overlay.mkdir(exist_ok=True)
excluded = {'OriginalAnalyticPrimitiveSnapshot.swift', 'OriginalAnalyticPrimitiveSnapshotProvider.swift',
    'OriginalAnalyticConeSnapshot.swift', 'OriginalAnalyticConeSnapshotProvider.swift'}
originals = sorted(p for p in (root / 'Sources/CADGeometry/OriginalSourceIssuance').rglob('*.swift')
    if p.name not in excluded)
commands = []
def run(command):
    commands.append(command)
    result = subprocess.run(command, timeout=120)
    if result.returncode: raise SystemExit(result.returncode)
def overlays(paths, prefix):
    result = []
    for path in paths:
        target = overlay / path.name
        target.write_text(prefix + path.read_text())
        if target.read_text()[len(prefix):] != path.read_text():
            raise RuntimeError('Overlay changed production source')
        result.append(target)
    return result
issued = overlays(originals, 'import CADGeometry\n')
run(common + ['-emit-library', '-static', '-emit-module', '-module-name', 'SourceIssuerCached',
    *map(str, issued), '-emit-module-path', str(output / 'SourceIssuerCached.swiftmodule'),
    '-o', str(output / 'libSourceIssuerCached.a')])
consumer = root / 'Sources/CADGeometry/NativeExactRelations'
names = ['DefaultNativeExactRelationResolver.swift', 'DefaultNativeExactRelationResolver+Sources.swift',
    'NativeExactIssuedSourceLaw.swift', 'NativeExactPreparedMap.swift', 'NativeExactRelationFailure.swift',
    'NativeExactRelationSource.swift', 'NativeExactParametricRelation.swift',
    'NativeExactCurveSurfaceResolving.swift', 'NativeExactSurfaceSurfaceResolving.swift']
consumers = [consumer / name for name in names]
prepared = overlays(consumers, 'import CADGeometry\nimport SourceIssuerCached\n')
proof = root / 'Tests/OriginalSourceIssuanceVerification/Sources/NativeConsumerProof/NativeConsumerProof.swift'
objects = []; archives = []
for module in ['CADCore', 'CADGeometry', 'HashTreeCollections', 'InternalCollectionsUtilities']:
    found = sorted(geometry.glob(f'out/Intermediates.noindex/*/{configuration}/{module}-t.build/Objects-normal/{architecture}/*.o'))
    if not found and args.lane == 'asan':
        merged = gp / (module + '.o')
        if merged.is_file(): found = [merged]
    if not found: raise RuntimeError('Missing cached object inventory: ' + module)
    objects.extend(found)
    archive = output / f'libCached{module}.a'; archive.unlink(missing_ok=True)
    run([str(swiftc.parent / 'llvm-ar') if wasm else 'ar', '-rcs', str(archive), *map(str, found)])
    archives.append(archive)
link_extra = []
if args.lane == 'embedded':
    unicode_library = Path(receipt['unicode_library']['path'])
    if digest(unicode_library) != receipt['unicode_library']['sha256']:
        raise RuntimeError('Changed Embedded Unicode runtime')
    link_extra = [str(unicode_library)]
artifact = output / ('NativeConsumerProof.wasm' if wasm else 'NativeConsumerProof')
run(common + ['-parse-as-library', '-I', str(output), *map(str, prepared), str(proof),
    str(output / 'libSourceIssuerCached.a'), *map(str, archives), *link_extra, '-o', str(artifact)])
run(['/usr/local/bin/node', str(root / 'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'), str(artifact)]
    if wasm else [str(artifact)])
changed_lower = {name: {'validated': value, 'current': digest(root / name)}
    for name, value in receipt['source_sha256'].items()
    if '/ExactRealRoot/' in name and digest(root / name) != value}
manifest = {'compiledSources': {str(p.relative_to(root)): digest(p) for p in originals + consumers + [proof]},
    'cachedInputs': {str(p): digest(p) for p in objects}, 'commands': commands,
    'toolchain': subprocess.check_output([str(swiftc), '--version'], text=True).strip(),
    'artifactSHA256': digest(artifact), 'lane': args.lane, 'cachedProviderPremises': premises,
    'cachedRuntimeReceipt': digest(receipt_path), 'cachedRuntimeArtifact': digest(old_proof),
    'changedLowerIntervalInputs': changed_lower,
    'scope': 'Current Native source preparation and checked handoff; cached lower contract. No solve/public query or upper target build. Latest DI0 interval integration is separate.'}
(output / 'native-consumer.json').write_text(json.dumps(manifest, indent=2) + '\n')
