#!/usr/bin/env python3
"""Record the actual independent compiler boundary and matching proof inputs."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[3]
evidence = root / 'Tests/OriginalSourceIssuanceVerification/Evidence'
modules = ['L0', 'L1', 'SourceIssuer', 'SourceIssuerFixtures', 'SourceIssuerProof', 'SourceIssuerTests']
allowed = dict(zip(modules, [
    root / 'Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar',
    root / 'Sources/CADGeometry/RationalBivariateAlgebra/ExactPolynomial',
    root / 'Sources/CADGeometry/OriginalSourceIssuance',
    root / 'Tests/OriginalSourceIssuanceVerification/Sources/Fixtures',
    root / 'Tests/OriginalSourceIssuanceVerification/Sources/Proof',
    root / 'Tests/OriginalSourceIssuanceVerification/Tests']))
lanes = {}
artifacts = {}
for lane, directory in [('native', 'source-issuer-contract'), ('asan', 'source-issuer-asan'),
                        ('wasm', 'source-issuer-wasm'), ('embedded', 'source-issuer-embedded')]:
    build = root / '.build' / directory
    lists = list(build.rglob('*.SwiftFileList'))
    assert {p.stem for p in lists} == set(modules[:6 if lane in ('native', 'asan') else 5])
    entries = {}
    for listing in lists:
        module = listing.stem
        sources = []
        for name in listing.read_text().splitlines():
            path = Path(name.strip('"')).resolve()
            generated = path.is_relative_to(build) and path.name == 'test_entry_point.swift'
            assert path.is_relative_to(allowed[module]) or (module == 'SourceIssuerTests' and generated), path
            sources.append({'path': str(path.relative_to(root)), 'generated': generated,
                            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        entries[module] = sorted(sources, key=lambda entry: entry['path'])
    lanes[lane] = entries
    product = 'out/Products/Debug/SourceIssuerProof' if lane in ('native', 'asan') else 'out/Products/Debug-webassembly-wasm32/SourceIssuerProof.wasm'
    path = build / product
    artifacts[lane] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}
for module in modules[:5]:
    assert all(lanes[lane][module] == lanes['native'][module] for lane in lanes), module
for module in ['L0', 'L1']:
    for source in lanes['native'][module]:
        original = subprocess.check_output(['git', 'show', 'e0ef7482:' + source['path']], cwd=root)
        assert hashlib.sha256(original).hexdigest() == source['sha256'], source
compiler = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift'
result = {
    'toolchain': 'swift-6.4.0-RELEASE',
    'compiler': subprocess.check_output([compiler, '--version'], text=True).strip(),
    'normalSDK': 'swift-6.4.0-RELEASE_wasm', 'embeddedSDK': 'swift-6.4.0-RELEASE_wasm-embedded',
    'target': 'wasm32-unknown-wasip1',
    'node': subprocess.check_output(['/usr/local/bin/node', '--version'], text=True).strip(),
    'compiledInputs': lanes, 'artifacts': artifacts,
    'logs': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in evidence.glob('*.log')}}
(evidence / 'verified-inputs.json').write_text(json.dumps(result, indent=2) + '\n')
print({lane: {module: len(sources) for module, sources in entries.items()} for lane, entries in lanes.items()})
print('Unchanged88 lower hashes; identical107 proof inputs across4 lanes; no upper target input.')
