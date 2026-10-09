#!/usr/bin/env python3
"""Verify complete issued maps and relations against checked lower products."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
from VerificationInputs import copy_input, require_unchanged_inputs
from RebuiltLowerCache import checked

parser = argparse.ArgumentParser()
parser.add_argument('--lane', choices=['native', 'asan', 'wasm', 'embedded'], default='native')
parser.add_argument('--lower-products', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
output = root / ('.build/handoff-map-' + args.lane)
output.mkdir(parents=True, exist_ok=True)
wasm = args.lane in ('wasm', 'embedded')
configuration = 'Debug-webassembly-wasm32' if wasm else 'Debug'
current = root / ('.build/handoff-' + args.lane) / 'out/Products' / configuration
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

if args.lower_products:
    cache = args.lower_products.resolve()
    rebuilt = checked(root, cache)
    l2_object = cache / 'L2.o'
    if not l2_object.is_file(): l2_object = next(iter(sorted((cache / 'L2.objlib').glob('*.o'))))
    product = {'path': str(l2_object), 'sha256': digest(l2_object),
        'scope': rebuilt['scope']}
else:
    cache = Path('/private/tmp/cad-domain-identity-completion-20261008/.build') / ('di-plane-opt-' + args.lane) / 'out/Products' / configuration
    evidence = root / 'Tests/OriginalDomainIdentityVerification/PlaneOptimizationEvidence'
    receipt = json.loads((evidence / 'receipt.json').read_text())

    product = receipt['products'][args.lane]
    if digest(Path(product['path'])) != product['sha256']:
        raise RuntimeError('Changed cached L2 runtime artifact')
    for name, expected in json.loads((evidence / 'source-hashes.json').read_text()).items():
        if '/OriginalDomainIdentity/' in name and not name.endswith('DESIGN.md'):
            if digest(root / name) != expected:
                raise RuntimeError('Changed cached L2 implementation: ' + name)
swift = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc')
if wasm:
    sdk_base = Path('/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1')
    sdk_data = json.loads((sdk_base / ('embedded-swift-sdk.json' if args.lane == 'embedded' else 'swift-sdk.json')).read_text())['targetTriples']['wasm32-unknown-wasip1']
    resources = sdk_base / sdk_data['swiftResourcesPath']
    toolset = json.loads((sdk_base / sdk_data['toolsetPaths'][0]).read_text())
    common = [str(swift), '-sdk', str(sdk_base / sdk_data['sdkRootPath']), '-target', 'wasm32-unknown-wasip1',
              '-resource-dir', str(resources), '-tools-directory', str(sdk_base / toolset['rootPath']),
              *toolset['swiftCompiler']['extraCLIOptions'],
              '-Xclang-linker', '-resource-dir', '-Xclang-linker', str(resources / 'clang')]
else:
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    common = [str(swift), '-sdk', sdk, '-target', 'arm64-apple-macos15.0']
    if args.lane == 'asan':
        common += ['-sanitize=address', '-Xlinker', '-dead_strip']
common += ['-swift-version', '6', '-package-name', 'originalsourceissuanceverification', '-I', str(output), '-I', str(current), '-I', str(cache)]
hashes = {}
sources = []
domain_output = root / ('.build/handoff-domain-' + args.lane)
coordinate_output = root / ('.build/handoff-coordinate-' + args.lane)
common += ['-I', str(coordinate_output)]
coordinate_receipt = json.loads((coordinate_output / 'receipt.json').read_text())
for name, expected in coordinate_receipt['inputs'].items():
    if digest(root / name) != expected: raise RuntimeError('Changed coordinate transfer premise: ' + name)
domain_receipt = json.loads((domain_output / 'receipt.json').read_text())
for name, expected in domain_receipt['inputs'].items():
    if name.startswith('Sources/') and digest(root / name) != expected:
        raise RuntimeError('Changed issued domain premise: ' + name)
common[common.index('-I'):common.index('-I')] = ['-I', str(domain_output)]
for name in ['OriginalIssuedMapCompiling.swift', 'OriginalIssuedMapPreparation.swift', 'OriginalIssuedSelectedMap.swift', 'DefaultOriginalIssuedMapCompiler.swift', 'NativeExactRelationFailure.swift', 'OriginalIssuedRelationPair.swift', 'OriginalIssuedRelation.swift', 'OriginalIssuedRelationResolving.swift', 'DefaultOriginalIssuedRelationResolver.swift', 'OriginalIssuedCurveSurfacePointResolving.swift', 'OriginalIssuedCurveSurfacePointIncidence.swift', 'OriginalIssuedCurveSurfacePoint.swift', 'OriginalIssuedCurveSurfacePointSet.swift', 'DefaultOriginalIssuedCurveSurfacePointResolver.swift']:
    source = root / 'Sources/CADGeometry/NativeExactRelations' / name
    sources.append(str(copy_input(source, output / name, root, hashes)))
commands = []
def run(command):
    commands.append(command); subprocess.run(command, check=True, timeout=120)
lower = cache if args.lower_products else Path('/private/tmp/cad-domain-identity-completion-20261008/.build') / ('di-consumer-' + args.lane) / 'out/Products' / configuration
common += ['-I', str(lower)]
run(common + ['-parse-as-library', '-emit-library', '-static', '-emit-module', '-module-name', 'IssuedMaps', '-D', 'SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION', *sources, '-emit-module-path', str(output / 'IssuedMaps.swiftmodule'), '-o', str(output / 'libIssuedMaps.a')])
if not args.lower_products:
    consumer_receipt = json.loads((root / ('Tests/OriginalDomainConsumerVerification/Evidence/' + args.lane + '-receipt.json')).read_text())
    for path, expected in consumer_receipt['products'].items():
        if any('/' + module + '.' in path for module in ['L3', 'L4', 'L5']):
            if digest(Path(path)) != expected:
                raise RuntimeError('Changed verified lower object: ' + path)
objects = []
archives = []
for directory, modules in [(current, ['L0', 'L1', 'SourceIssuer']), (cache, ['DI0', 'L2']), (lower, ['L3', 'L4', 'L5'])]:
    for module in modules:
        merged = directory / (module + '.o')
        found = [merged] if merged.is_file() else sorted((directory / (module + '.objlib')).glob('*.o'))
        if not found:
            raise RuntimeError('Missing checked module object inventory: ' + module)
        objects.extend(found)
        archive = output / ('lib' + module + '.a')
        archive.unlink(missing_ok=True)
        run([str(swift.parent / 'llvm-ar') if wasm else 'ar', '-rcs', str(archive), *map(str, found)])
        archives.append(str(archive))
object_hashes = {str(p): digest(p) for p in objects}
proof = str(copy_input(root / 'Tests/OriginalSourceIssuanceVerification/Sources/DomainProof/Proof.swift',
                       output / 'Proof.swift', root, hashes))
p = Path(proof)
p.write_text(p.read_text().replace('import IssuedDomainBinding\n', ''))
artifact = output / ('DomainProof.wasm' if wasm else 'DomainProof')
run(common + ['-parse-as-library', '-D', 'SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION', proof, str(copy_input(root / 'Tests/OriginalSourceIssuanceVerification/Sources/Fixtures/NativeSource.swift', output / 'NativeSource.swift', root, hashes)), str(output / 'libIssuedMaps.a'), str(coordinate_output / 'libOriginalCoordinateTransfer.a'), str(domain_output / 'libDI.a'),
              *archives, '-o', str(artifact)])
run(['/usr/local/bin/node', str(root / 'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'), str(artifact)] if wasm else [str(artifact)])
require_unchanged_inputs(root, hashes)
for path, expected in object_hashes.items():
    if digest(Path(path)) != expected:
        raise RuntimeError('Changed module object during bridge verification: ' + path)
(output / 'receipt.json').write_text(json.dumps({'inputs': hashes, 'commands': commands,
    'lowerPremise': product, 'lane': args.lane, 'artifact': digest(artifact),
    'objects': object_hashes}, indent=2) + '\n')
