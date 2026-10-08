#!/usr/bin/env python3
"""Retain bounded bridge receipts and their actual source/behavioral evidence."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[3]
destination = root / 'Tests/OriginalSourceIssuanceVerification/CoordinateTransferEvidence'
destination.mkdir(exist_ok=True)
files = set()
for lane in ['native', 'asan', 'wasm', 'embedded']:
    receipt = root / ('.build/handoff-coordinate-' + lane) / 'receipt.json'
    data = json.loads(receipt.read_text())
    for name, expected in data['inputs'].items():
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise RuntimeError('Changed verified bridge input: ' + name)
    files.update(data['inputs'])
    shutil.copy2(receipt, destination / (lane + '-receipt.json'))
    for stem in ['coordinate-' + lane, 'coordinate-current-' + lane]:
        source = root / '.build/handoff-evidence' / (stem + '.log')
        if source.exists():
            shutil.copy2(source, destination / source.name)
for stem in ['selected-wasm-runtime', 'selected-embedded-runtime']:
    source = root / '.build/handoff-evidence' / (stem + '.log')
    shutil.copy2(source, destination / source.name)
for component in ['ExactScalar', 'ExactPolynomial']:
    for path in (root / 'Sources/CADGeometry/RationalBivariateAlgebra' / component).glob('*.swift'):
        files.add(str(path.relative_to(root)))
files.update(['Tests/OriginalSourceIssuanceVerification/Sources/Fixtures/ScalarTransportFixtures.swift',
              'Tests/OriginalSourceIssuanceVerification/Scripts/VerifyCoordinateTransfer.py'])
manifest = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sorted(files)}
(destination / 'source-hashes.json').write_text(json.dumps(manifest, indent=2) + '\n')
