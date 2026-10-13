"""Verify the real public offset validator with its exact production source closure."""
from pathlib import Path
import ast
import hashlib
import json
import os
import signal
import subprocess
import sys
import time

r = Path.cwd()
lane = sys.argv[1]
assert lane in ('native', 'asan', 'wasm', 'embedded')
out = r / '.build/coons-offset-caller-green-20261014' / lane
out.mkdir(parents=True, exist_ok=True)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
canonical = r / '.build/trimmed-fold-canonical-20261013' / lane
edge = r / '.build/trimmed-fold-20261013' / ('edge-' + lane)
plan = json.loads((canonical / 'plan.json').read_text())
geometry_inputs = {p: h for p, h in plan['inputs'].items() if '/Sources/CADGeometry/' in p}
assert len(geometry_inputs) == 2054
for p, h in geometry_inputs.items():
    assert sha(p) == h, p
record = json.loads((canonical / 'CADGeometry.json').read_text())
assert record['exitCode'] == 0 and record['stopReason'] is None
assert sha(canonical / 'CADGeometry.log') == record['logSHA256']
def normalized_geometry_command(command):
    result, imports = [], []
    i = 0
    while i < len(command):
        if command[i] == '-I':
            imports.append(command[i + 1])
            i += 2
        elif command[i] == '-package-name':
            result.extend([command[i], command[i + 1].lower()])
            i += 2
        else:
            result.append(command[i])
            i += 1
    return result, sorted(imports)
# Native reissued package-aligned metadata; the unchanged object used the same
# normalized package identity and import locations (none contain a Core override).
assert normalized_geometry_command(record['command']) == normalized_geometry_command(plan['commands']['CADGeometry'])
geometry_products = [canonical / 'CADGeometry.swiftmodule', canonical / 'libCADGeometry.a']
edge_record = json.loads((edge / 'premises.json').read_text())
for p, h in edge_record['products'].items():
    assert sha(p) == h, p
# The package-aligned Topology metadata is generated from the unchanged 143 inputs.
topology_metadata = canonical / 'CADTopology.swiftmodule'
metadata_record = json.loads((canonical / 'CADTopology-package-metadata.json').read_text())
assert metadata_record['exitCode'] == 0
assert sha(canonical / 'CADTopology-package-metadata.log') == metadata_record['logSHA256']
topology_inputs = sorted((r / 'Sources/CADTopology').rglob('*.swift'))
assert len(topology_inputs) == 143
prior_topology = json.loads((r / '.build/trimmed-fold-20261013/green-native/premises.json').read_text())['sources']
for p in topology_inputs:
    assert sha(p) == prior_topology[str(p)], p

base = json.loads((edge / 'compile.json').read_text())['command']
flags = [v for v in base if not v.endswith('.swift') and not v.startswith('@') and not v.endswith('.a')]
for option in ('-o', '-module-name'):
    if option in flags:
        i = flags.index(option)
        del flags[i:i + 2]
flags[flags.index('-package-name') + 1] = 'nativeexactrelationverification'
flags[1:1] = ['-I', str(out), '-I', str(canonical)]
prior = Path(next(v[1:] for v in base if v.startswith('@')))
dependencies = [Path(json.loads(v)) for v in prior.read_text().splitlines() if v]
dependencies = [p for p in dependencies if any(t in str(p) for t in (
    '/CADCore-t.build/', '/CADCore.objlib/', '/HashTreeCollections-t.build/', '/HashTreeCollections.objlib/',
    '/InternalCollectionsUtilities-t.build/', '/InternalCollectionsUtilities.objlib/'))
    or p.name in ('CADCore.o', 'HashTreeCollections.o', 'InternalCollectionsUtilities.o')]
assert dependencies and any('CADCore' in str(p) for p in dependencies)
products = json.loads((r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NONLINEAR-COLLAPSE-01/products.json').read_text())
for p in dependencies:
    assert sha(p) == products[str(p)], p

sources = {
    'CADModeling': [r / 'Sources/CADModeling/SharedSheetOffset/OffsetResultValidating.swift'],
    'CADKernel': [r / 'Sources/CADKernel' / p for p in (
        'OriginalOffsetFeasibility/DefaultOffsetResultValidator.swift',
        'OriginalOffsetFeasibility/OffsetFeasibilityInvocation.swift',
        'OriginalOffsetFeasibility/OffsetFeasibilityLimits.swift',
        'OriginalOffsetFeasibility/OffsetExactScalarAdmission.swift',
        'OriginalOffsetFeasibility/OriginalOffsetNativeSelfContact.swift',
        'OriginalOffsetFeasibility/OriginalOffsetCoonsSelfContact.swift',
        'OriginalBoundaryClipping/OriginalExactFaceBoundaryIssuer.swift',
        'OriginalBoundaryClipping/OriginalExactFaceBoundaryLoops.swift')],
}
fixture = r / 'Tests/OriginalPublicAcceptanceVerification/CoonsOffsetCallerAcceptance.swift'
face = r / 'Tests/OriginalPublicAcceptanceVerification/TrimmedFoldObservation.swift'
proof_out = out / 'caller'
proof_out.mkdir(exist_ok=True)
helper = proof_out / 'FoldFace.swift'
helper.write_text(face.read_text().replace('@main struct TrimmedFoldObservation', 'struct TrimmedFoldObservation'))
frozen_fixture = proof_out / ('Fixture-' + sha(fixture) + '.swift')
frozen_fixture.write_bytes(fixture.read_bytes())
inputs = dict(geometry_inputs)
inputs.update({str(p): sha(p) for ps in sources.values() for p in ps})
inputs.update({str(p): sha(p) for p in topology_inputs + [fixture, frozen_fixture, face, helper, Path(__file__).resolve()]})
used_products = {str(p): sha(p) for p in dependencies + geometry_products + [topology_metadata, edge / 'libCADTopology.a']}
# Freeze all premises before any compilation or cached-product execution.
(proof_out / 'input-plan.json').write_text(json.dumps(dict(inputs=inputs, products=used_products,
    productionSourceCounts={k: len(v) for k, v in sources.items()},
    scope='Original production modules and public validator; Geometry2054/Topology143/Core reused; no source ports/stubs/legacy callback replay.'), indent=2) + '\n')
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[fn], type_ignores=[]), '<bounded-run>', 'exec'))
deadline = time.monotonic() + 1200
for module, paths in sources.items():
    rsp = out / (module + '.rsp')
    rsp.write_text('\n'.join(json.dumps(str(p)) for p in paths) + '\n')
    command = flags + ['-whole-module-optimization', '-enable-testing', '-emit-module',
        '-emit-module-path', str(out / (module + '.swiftmodule')), '-module-name', module,
        '-emit-library', '-static', '@' + str(rsp), '-o', str(out / ('lib' + module + '.a'))]
    cache = out / (module + '-premises.json')
    if cache.exists():
        retained = json.loads(cache.read_text())
        receipt = json.loads((out / (module + '.json')).read_text())
        assert receipt['exitCode'] == 0 and receipt['command'] == command
        assert sha(out / (module + '.json')) == retained['recordSHA256']
        assert sha(out / (module + '.log')) == receipt['logSHA256']
        for p, h in retained['inputs'].items():
            assert sha(p) == h, p
        for p, h in retained['products'].items():
            assert sha(p) == h, p
        for p, h in retained['dependencies'].items():
            assert sha(p) == h, p
        print(lane, module, 'reuse matching production receipt', flush=True)
    else:
        run(command, module, seconds=max(1, deadline - time.monotonic()))
        cache.write_text(json.dumps(dict(inputs={str(p): sha(p) for p in paths},
            products={str(p): sha(p) for p in (out / (module + '.swiftmodule'), out / ('lib' + module + '.a'))},
            dependencies=used_products, recordSHA256=sha(out / (module + '.json'))), indent=2) + '\n')
    for p in (out / (module + '.swiftmodule'), out / ('lib' + module + '.a')):
        used_products[str(p)] = sha(p)

production_out = out
out = proof_out
dep_rsp = out / 'dependencies.rsp'
dep_rsp.write_text('\n'.join(json.dumps(str(p)) for p in dependencies) + '\n')
exe = out / ('Proof.wasm' if lane in ('wasm', 'embedded') else 'Proof')
libraries = [production_out / ('lib' + t + '.a') for t in ('CADKernel', 'CADModeling')]
libraries += [canonical / 'libCADGeometry.a', edge / 'libCADTopology.a']
command = flags + ['-D', 'COONS_RECEIPT_CONNECTED', '-module-name', 'CoonsOffsetCallerAcceptance',
    str(frozen_fixture), str(helper)] + list(map(str, libraries)) + ['@' + str(dep_rsp), '-o', str(exe)]
run(command, 'fixture', seconds=max(1, deadline - time.monotonic()))
used_products[str(exe)] = sha(exe)
runtime = [str(exe)]
if lane in ('wasm', 'embedded'):
    wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
    assert sha(wrapper) == wrapper.stem
    inputs[str(wrapper)] = sha(wrapper)
    runtime = ['/usr/local/bin/node', str(wrapper), str(exe)]
modes = sys.argv[2:] or ['caller']
for mode in modes:
    for p, h in inputs.items():
        assert sha(p) == h, p
    for p, h in used_products.items():
        assert sha(p) == h, p
    os.environ['CAD_PROOF_GROUP'] = mode
    run(runtime, mode, seconds=max(1, deadline - time.monotonic()))
for p, h in inputs.items():
    assert sha(p) == h, p
for p, h in used_products.items():
    assert sha(p) == h, p
(out / 'acceptance-premises.json').write_text(json.dumps(dict(inputs=inputs, products=used_products,
    modes=modes, scope='Real public DefaultOffsetResultValidator and complete trimmed-fold material cell; no whole-family or whole-Kernel acceptance.'), indent=2) + '\n')
