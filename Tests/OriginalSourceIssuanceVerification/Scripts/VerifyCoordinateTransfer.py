#!/usr/bin/env python3
"""Build only the coordinate bridge against checked cached L2 and current L0/L1."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
from VerificationInputs import copy_input, require_unchanged_inputs

parser = argparse.ArgumentParser()
parser.add_argument('--lane', choices=['native', 'asan', 'wasm', 'embedded'], default='native')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
output = root / ('.build/handoff-coordinate-' + args.lane)
output.mkdir(parents=True, exist_ok=True)
wasm = args.lane in ('wasm', 'embedded')
configuration = 'Debug-webassembly-wasm32' if wasm else 'Debug'
current = root / ('.build/handoff-' + args.lane) / 'out/Products' / configuration
cache = Path('/private/tmp/cad-domain-identity-completion-20261008/.build') / ('di-plane-opt-' + args.lane) / 'out/Products' / configuration
evidence = root / 'Tests/OriginalDomainIdentityVerification/PlaneOptimizationEvidence'
receipt = json.loads((evidence / 'receipt.json').read_text())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

product = receipt['products'][args.lane]
if digest(Path(product['path'])) != product['sha256']:
    raise RuntimeError('Changed cached L2 runtime artifact')
for name, expected in json.loads((evidence / 'source-hashes.json').read_text()).items():
    if '/ExactRealRoot/' in name and not name.endswith('DESIGN.md'):
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
common += ['-swift-version', '6', '-package-name', 'originalsourceissuanceverification', '-I', str(current), '-I', str(cache), '-I', str(output)]
hashes = {}
sources = []
for name in ['ExactOriginalScalarTransferring.swift', 'ExactOriginalScalarTransferReceipt.swift',
             'DefaultExactOriginalScalarTransporter.swift', 'OriginalCoordinateTransportState.swift',
             'OriginalCoordinateTransportState+Roots.swift']:
    sources.append(str(copy_input(root / 'Sources/CADGeometry/RationalBivariateAlgebra/ExactRealRoot' / name,
                                  output / name, root, hashes)))
commands = []
def run(command):
    commands.append(command)
    subprocess.run(command, check=True, timeout=120)
run(common + ['-parse-as-library', '-emit-library', '-static', '-emit-module', '-module-name',
              'OriginalCoordinateTransfer', '-D', 'ORIGINAL_COORDINATE_ISOLATED_VERIFICATION', *sources,
              '-emit-module-path', str(output / 'OriginalCoordinateTransfer.swiftmodule'),
              '-o', str(output / 'libOriginalCoordinateTransfer.a')])
objects = []
archives = []
for directory, modules in [(current, ['L0', 'L1']), (cache, ['DI0', 'L2'])]:
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
proof = str(copy_input(root / 'Tests/OriginalSourceIssuanceVerification/Sources/CoordinateProof/Proof.swift',
                       output / 'Proof.swift', root, hashes))
artifact = output / ('CoordinateProof.wasm' if wasm else 'CoordinateProof')
run(common + ['-parse-as-library', proof, str(output / 'libOriginalCoordinateTransfer.a'),
              *archives, '-o', str(artifact)])
run(['/usr/local/bin/node', str(root / 'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'), str(artifact)] if wasm else [str(artifact)])
require_unchanged_inputs(root, hashes)
for path, expected in object_hashes.items():
    if digest(Path(path)) != expected:
        raise RuntimeError('Changed module object during bridge verification: ' + path)
(output / 'receipt.json').write_text(json.dumps({'inputs': hashes, 'commands': commands,
    'cachedL2Proof': product, 'lane': args.lane, 'artifact': digest(artifact),
    'objects': object_hashes}, indent=2) + '\n')
