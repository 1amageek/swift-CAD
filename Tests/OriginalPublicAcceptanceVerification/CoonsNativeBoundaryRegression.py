#!/usr/bin/env python3
"""Run the changed Native boundary bodies without selecting unrelated lower adapters."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.output.resolve()
work.mkdir(parents=True, exist_ok=False)
original = root / 'Tests/OriginalNativeConsumerIntakeVerification/Consumers.py'
source = original.read_text()
# This boundary-only route uses exact-rational Native chart issuance directly,
# not finite OriginalExact charts, offset/spatial sources, or M5 identities.
# The accepted lower graph and all selected Native/periodic DTO inputs remain
# hash-admitted by Consumers.py. Package.swift is not re-resolved or compiled.
unselected = [
    'Tests/OriginalGraphRelationVerification/Package.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalFiniteBSplineChartPreparer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalOffsetLawIssuer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalSpatialChartIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/OriginalParameterIdentity.swift']
source = source.replace('root = Path(__file__).resolve().parents[2]', 'root = Path(' + repr(str(root)) + ')')
needle = "    path = Path(name)\n    if path.is_relative_to(root) and not path.is_relative_to(root / '.build'):"
replacement = "    path = Path(name)\n    if name in " + repr({str(root / name) for name in unselected}) + ":\n        continue\n    if path.is_relative_to(root) and not path.is_relative_to(root / '.build'):"
assert source.count(needle) == 1
source = source.replace(needle, replacement)
needle = "consumers += sorted((root/'Sources/CADGeometry/OriginalSurfaceEmbedding').glob('*Exact*.swift'))"
assert source.count(needle) == 1
source = source.replace(needle, '')
start = source.index("module('NativeExactSelfFixtures'")
end = source.index("module('NativeKernelAdapters'", start)
block = source[start:end]
objects_start = block.index('objects = ')
objects_end = block.index('\nproof = ', objects_start)
runtime_start = block.index('def runtime(')
runtime_end = block.index("\nfor group in ['diagonal'", runtime_start)
source = source[:start] + block[objects_start:objects_end] + '\n' + block[runtime_start:runtime_end] + '\n' + source[end:]
source = source.replace('[executable,boundary]', '[boundary]')
source = source.replace('Actual current Native source/DI/L5/self consumer;', 'Actual changed Native source/DI/L5/boundary consumer; M5/self and finite OriginalExact/offset/spatial adapters are unselected;')
source_path = work / 'boundary-driver.py'
source_path.write_text(source)
command = ['python3', str(source_path), args.lane, '--output', str(work / 'verification')]
(work / 'adaptation.json').write_text(json.dumps(dict(originalDriver=str(original),
    originalSHA256=hashlib.sha256(original.read_bytes()).hexdigest(),
    adaptedSHA256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
    excludedUnselectedLowerInputs=unselected, command=command), indent=2) + '\n')
result = subprocess.run(command, cwd=root, timeout=900)
raise SystemExit(result.returncode)
