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
parser.add_argument('--issuer-cache', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
swiftc = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc')
output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
geometry = args.geometry_cache.resolve(); issuer = args.issuer_cache.resolve()
wasm = args.lane in ('wasm', 'embedded')
configuration = 'Debug-webassembly-wasm32' if wasm else 'Debug'
architecture = 'wasm32' if wasm else 'arm64'
gp = geometry / 'out/Products' / configuration; ip = issuer / 'out/Products' / configuration
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
common += ['-swift-version', '6', '-package-name', 'nativeexactrelationverification', '-I', str(gp), '-I', str(ip)]
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
    'Sources/CADGeometry/PeriodicBSpline/']
exact = ['Sources/CADGeometry/BSplineCurve3D.swift', 'Sources/CADGeometry/BSplineSurface3D.swift',
    'Sources/CADGeometry/AnalyticSurface3D.swift', 'Sources/CADGeometry/AnalyticBasis.swift']
premises = {name: expected_hash for name, expected_hash in receipt['source_sha256'].items()
    if name in exact or any(name.startswith(prefix) for prefix in prefixes)}
for name, expected_hash in premises.items():
    if digest(root / name) != expected_hash:
        raise RuntimeError('Changed cached provider premise: ' + name)
names = ['BSplineCurve3D+OriginalSourceReading.swift', 'BSplineSurface3D+OriginalSourceReading.swift',
         'OriginalBSplineCurveSnapshotProvider.swift', 'OriginalBSplineSurfaceSnapshotProvider.swift',
         'OriginalAnalyticPrimitiveSnapshot.swift', 'OriginalAnalyticPrimitiveSnapshotProvider.swift',
         'OriginalAnalyticConeSnapshot.swift', 'OriginalAnalyticConeSnapshotProvider.swift']
sources = [root / 'Sources/CADGeometry/OriginalSourceIssuance' / name for name in names]
sources.append(root / 'Tests/OriginalSourceIssuanceVerification/Sources/GeometryProof/CachedAdmissionConformance.swift')
sources.append(root / 'Sources/CADGeometry/AnalyticBasis.swift')
proof = root / 'Tests/OriginalSourceIssuanceVerification/Sources/GeometryProof/GeometryProof.swift'
commands = []
def run(command):
    commands.append(command)
    result = subprocess.run(command, timeout=120)
    if result.returncode:
        raise SystemExit(result.returncode)
run(common + ['-emit-library', '-static', '-emit-module', '-module-name', 'SourceGeometryAdapters',
    '-D', 'ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION', *map(str, sources),
    '-emit-module-path', str(output / 'SourceGeometryAdapters.swiftmodule'),
    '-o', str(output / 'libSourceGeometryAdapters.a')])
# Object names are never inferred from declarations: use the existing build's
# complete module object inventories, excluding executable and test objects.
objects = []
archives = []
for cache, modules in [(geometry, ['CADCore', 'CADGeometry', 'HashTreeCollections', 'InternalCollectionsUtilities']),
                       (issuer, ['L0', 'L1', 'SourceIssuer'])]:
    for module in modules:
        found = sorted(cache.glob(f'out/Intermediates.noindex/*/{configuration}/{module}-t.build/Objects-normal/{architecture}/*.o'))
        if not found and args.lane == 'asan':
            # This validated ASAN cache retains one merged object per module.
            merged = cache / 'out/Products' / configuration / (module + '.o')
            if merged.is_file(): found = [merged]
        if not found:
            raise RuntimeError(f'Missing cached object inventory: {module}')
        objects.extend(found)
        archive = output / f'libCached{module}.a'
        archive.unlink(missing_ok=True)
        archiver = str(swiftc.parent / 'llvm-ar') if wasm else 'ar'
        run([archiver, '-rcs', str(archive), *map(str, found)])
        archives.append(archive)
link_extra = []
if args.lane == 'embedded':
    unicode_library = Path(receipt['unicode_library']['path'])
    if digest(unicode_library) != receipt['unicode_library']['sha256']:
        raise RuntimeError('Changed Embedded Unicode runtime library')
    link_extra += [str(unicode_library)]
artifact = output / ('GeometryProof.wasm' if wasm else 'GeometryProof')
run(common + ['-parse-as-library', '-I', str(output), str(proof),
    str(output / 'libSourceGeometryAdapters.a'), *map(str, archives), *link_extra, '-o', str(artifact)])
if wasm:
    run(['/usr/local/bin/node', str(root / 'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'), str(artifact)])
else: run([str(artifact)])
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {'compiledSources': {str(p.relative_to(root)): digest(p) for p in sources + [proof]},
    'cachedInputs': {str(p): digest(p) for p in objects}, 'commands': commands,
    'toolchain': subprocess.check_output([str(swiftc), '--version'], text=True).strip(),
    'artifactSHA256': digest(artifact), 'lane': args.lane, 'cachedProviderPremises': premises,
    'cachedRuntimeReceipt': digest(receipt_path), 'cachedRuntimeArtifact': digest(old_proof),
    'scope': 'Actual Native/analytic providers and local/image laws; no upper target was rebuilt.'}
(output / 'geometry-adapters.json').write_text(json.dumps(manifest, indent=2) + '\n')
