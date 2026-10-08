"""Verify merged Native preparation using current issuer and checked lower caches."""
import hashlib
import json
from pathlib import Path
import subprocess

from VerificationInputs import copy_input, require_unchanged_inputs

root = Path(__file__).resolve().parents[3]
output = root / '.build/source-main-preparation'
output.mkdir(parents=True, exist_ok=True)
current = root / '.build/source-main-native/out/Products/Debug'
domain_root = Path('/private/tmp/cad-domain-identity-completion-20261008')
optimized = domain_root / '.build/di-plane-opt-native/out/Products/Debug'
lower = domain_root / '.build/di-consumer-native/out/Products/Debug'
geometry = Path('/private/tmp/cad-lower-public-main-integration-20261008/.build/public-native/out/Products/Debug')
swiftc = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc'
hashes, products, commands = {}, {}, []


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


consumer_receipt = json.loads((root / 'Tests/OriginalDomainConsumerVerification/Evidence/native-receipt.json').read_text())
for path, expected in consumer_receipt['cache_premises']['products'].items():
    assert digest(Path(path)) == expected, 'Changed geometry cache: ' + path
    products[path] = expected
for name, expected in consumer_receipt['cache_premises']['premises'].items():
    assert digest(root / name) == expected, 'Changed geometry premise: ' + name
for name, expected in consumer_receipt['compiled_sources'].items():
    if any('/' + layer + '/' in name for layer in ['ExactPolynomial', 'ExactRealCell', 'ExactRealTopology', 'ExactParametricRelation', 'ExactParameterDomain']):
        assert digest(root / name) == expected, 'Changed lower premise: ' + name
optimization = root / 'Tests/OriginalDomainIdentityVerification/PlaneOptimizationEvidence'
optimized_receipt = json.loads((optimization / 'receipt.json').read_text())
optimized_proof = optimized_receipt['products']['native']
assert digest(Path(optimized_proof['path'])) == optimized_proof['sha256']
for name, expected in json.loads((optimization / 'source-hashes.json').read_text()).items():
    if any('/' + layer + '/' in name for layer in ['ExactScalar', 'ExactPolynomial', 'ExactRealRoot', 'ExactParameterDomain']):
        assert digest(root / name) == expected, 'Changed optimized lower premise: ' + name

sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
common = [swiftc, '-sdk', sdk, '-target', 'arm64-apple-macos15.0', '-swift-version', '6',
          '-package-name', 'nativeexactrelationverification']
for folder in [current, output, optimized, lower, geometry]:
    common += ['-I', str(folder)]


def run(command):
    commands.append(command)
    subprocess.run(command, check=True, timeout=120)


def snapshots(module, files):
    folder = output / module
    folder.mkdir(exist_ok=True)
    return [str(copy_input(path, folder / path.name, root, hashes)) for path in files]


def module(name, files, define):
    run(common + ['-parse-as-library', '-emit-module', '-emit-library', '-static',
        '-module-name', name, '-D', define, *snapshots(name, files),
        '-emit-module-path', str(output / (name + '.swiftmodule')),
        '-o', str(output / ('lib' + name + '.a'))])


domain = root / 'Sources/CADGeometry/OriginalDomainIdentity'
files = sorted(p for p in domain.rglob('*.swift') if 'ExactParameterDomain' not in p.parts)
module('DI', files, 'ORIGINAL_DOMAIN_ISOLATED_VERIFICATION')
issuer = root / 'Sources/CADGeometry/OriginalSourceIssuance'
module('SourceGeometryAdapters', [issuer / name for name in [
    'BSplineCurve3D+OriginalSourceReading.swift', 'BSplineSurface3D+OriginalSourceReading.swift',
    'OriginalBSplineCurveSnapshotProvider.swift', 'OriginalBSplineSurfaceSnapshotProvider.swift']],
    'ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION')

objects = [current / (name + '.o') for name in ['L0', 'L1', 'SourceIssuer']]
objects += [optimized / (name + '.o') for name in ['DI0', 'L2']]
objects += [lower / (name + '.o') for name in ['L3', 'L4', 'L5']]
objects += [geometry / (name + '.o') for name in ['CADCore', 'CADGeometry', 'HashTreeCollections', 'InternalCollectionsUtilities']]
for path in objects:
    products[str(path)] = digest(path)
    if path.parent in (lower, geometry):
        assert products[str(path)] == consumer_receipt['products'][str(path)], 'Changed cached object: ' + str(path)

native = sorted((root / 'Sources/CADGeometry/NativeExactRelations').glob('*.swift'))
proof = root / 'Tests/OriginalSourceIssuanceVerification/Sources/MergedPreparationProof/MergedPreparationProof.swift'
artifact = output / 'MergedPreparationProof'
run(common + ['-parse-as-library', '-D', 'NATIVE_DOMAIN_ISOLATED_VERIFICATION',
    *snapshots('NativePreparation', native + [proof]),
    str(output / 'libDI.a'), str(output / 'libSourceGeometryAdapters.a'),
    *map(str, objects), '-o', str(artifact)])
run([str(artifact)])
module('NativeDomainAdapters', native, 'NATIVE_DOMAIN_ISOLATED_VERIFICATION')
fixture_root = root / 'Tests/NativeExactRelationVerification/Sources/Fixtures'
module('ConsumerFixtures', [fixture_root / name for name in [
    'NativeExactFixtures.swift', 'FinalPublicationAdmission.swift']],
    'NATIVE_DOMAIN_ISOLATED_VERIFICATION')
public_proof = root / 'Tests/OriginalDomainConsumerVerification/Sources/Proof/Proof.swift'
public_artifact = output / 'MergedDomainConsumerProof'
run(common + ['-parse-as-library', *snapshots('PublicProof', [public_proof]),
    str(output / 'libConsumerFixtures.a'), str(output / 'libNativeDomainAdapters.a'),
    str(output / 'libDI.a'), str(output / 'libSourceGeometryAdapters.a'),
    *map(str, objects), '-o', str(public_artifact)])
run([str(public_artifact)])
require_unchanged_inputs(root, hashes)
for path, expected in products.items():
    assert digest(Path(path)) == expected, 'Cache changed during verification: ' + path
manifest = {'compiledSources': hashes, 'reusedProducts': products, 'commands': commands,
    'artifactSHA256': digest(artifact), 'publicArtifactSHA256': digest(public_artifact),
    'scope': 'Merged source/domain Native preparation and existing public parameter CS/SSI consumers; checked lower execution, no upper target build.'}
(output / 'receipt.json').write_text(json.dumps(manifest, indent=2) + '\n')
