#!/usr/bin/env python3
"""Compare the two actual dispatchers without rebuilding their cached dependencies."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
proof = Path(__file__).resolve().parent
output = root / '.build/legacy-plane-torus'
cache = output / 'cache'
snapshot = json.loads((output / 'cache-inputs.json').read_text())
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
for name, expected in snapshot['copiedInputs'].items():
    if digest(root / name) != expected:
        raise RuntimeError('Changed dependency snapshot: ' + name)
source = root / 'Sources/CADGeometry/PlaneTorusSurfaceIntersector.swift'
baseline = subprocess.check_output(['git', 'show', 'a87b7853:Sources/CADGeometry/PlaneTorusSurfaceIntersector.swift'], cwd=root)
removed_types = baseline.index(b'    private struct TrigonometricPolynomial')
verifier = baseline.index(b'    private let verifier')
removed_helpers = baseline.index(b'    private func configuration(')
axial = baseline.index(b'    private func axialSection(')
expected = baseline[:removed_types] + baseline[verifier:removed_helpers] + baseline[axial:]
if source.read_bytes() != expected:
    raise RuntimeError('The deletion changes a retained production body')
input_paths = [source, proof / 'Proof.swift', proof / 'Wrapper.swift', Path(__file__).resolve()]
input_hashes = {str(p.relative_to(root)): digest(p) for p in input_paths}
for name in ['Proof', 'Wrapper']:
    (output / (name + 'Input.swift')).write_bytes((proof / (name + '.swift')).read_bytes())
(output / 'Before.swift').write_bytes(b'@testable import CADGeometry\n' + baseline)
(output / 'After.swift').write_bytes(b'@testable import CADGeometry\n' + expected)
swift = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc'
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
common = [swift, '-swift-version', '6', '-sdk', sdk, '-target', 'arm64-apple-macos15.0', '-I', str(cache), '-I', str(output)]
commands = []
def run(command):
    commands.append(command)
    subprocess.run(command, check=True, timeout=90)
for module, name in [('LegacyPlaneTorus', 'Before'), ('CleanPlaneTorus', 'After')]:
    run(common + ['-parse-as-library', '-emit-library', '-static', '-emit-module', '-module-name', module,
        str(output / (name + '.swift')), str(output / 'WrapperInput.swift'),
        '-emit-module-path', str(output / (module + '.swiftmodule')), '-o', str(output / ('lib' + module + '.a'))])
run(common + ['-parse-as-library', str(output / 'ProofInput.swift'), str(output / 'libLegacyPlaneTorus.a'),
    str(output / 'libCleanPlaneTorus.a'), *[str(cache / (name + '.o')) for name in
    ['CADGeometry', 'CADCore', 'HashTreeCollections', 'InternalCollectionsUtilities']], '-o', str(output / 'CleanupProof')])
run([str(output / 'CleanupProof')])
for name, expected_hash in snapshot['copiedInputs'].items():
    if digest(root / name) != expected_hash:
        raise RuntimeError('Dependency snapshot changed during execution: ' + name)
for name, expected_hash in input_hashes.items():
    if digest(root / name) != expected_hash:
        raise RuntimeError('Input changed during execution: ' + name)
(proof / 'receipt.json').write_text(json.dumps({'baselineCommit': 'a87b7853', 'baselineSha256': hashlib.sha256(baseline).hexdigest(),
    'inputs': input_hashes,
    'cacheSnapshot': snapshot, 'commands': commands, 'artifactSha256': digest(output / 'CleanupProof'),
    'scope': 'Native actual producer differential; cached dependency semantics, no fresh whole-module or portable build'}, indent=2) + '\n')
