"""Verify the original drafted sheet through both production publication branches."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time

r = Path.cwd()
lane = sys.argv[1]
assert lane in ('native', 'asan', 'wasm', 'embedded')
source_only = sys.argv[2:] == ['source']
out = r / '.build/drafted-sheet-20261014' / lane
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[fn], type_ignores=[]), '<bounded-run>', 'exec'))

inputs, products = {}, {}
for name, plan_name in [('CADGeometry', 'plan.json'), ('CADIR', 'IR-plan.json'), ('CADModeling', 'Modeling-plan.json')]:
    plan = json.loads((out / plan_name).read_text())
    for p, h in plan['inputs'].items():
        assert sha(p) == h, p
        inputs[p] = h
    record = json.loads((out / (name + '.json')).read_text())
    assert record['exitCode'] == 0 and record['stopReason'] is None
    assert sha(out / (name + '.log')) == record['logSHA256']
    cached = json.loads((out / (name + '-generation-premises.json')).read_text())
    assert sha(out / (name + '.json')) == cached['recordSHA256']
    assert cached['inputs'] == plan['inputs']
    for p, h in cached['products'].items():
        assert sha(p) == h, p
        products[p] = h

edge = r / '.build/trimmed-fold-20261013' / ('edge-' + lane)
canonical = r / '.build/trimmed-fold-canonical-20261013' / lane
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
authority = json.loads((r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NONLINEAR-COLLAPSE-01/products.json').read_text())
for p in dependencies:
    assert sha(p) == authority[str(p)], p
    products[str(p)] = sha(p)
metadata = {}
def collect(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key.startswith('/') and isinstance(item, str) and len(item) == 64:
                metadata[key] = item
            else:
                collect(item)
    elif isinstance(value, list):
        for item in value:
            collect(item)
collect(json.loads((r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-TRIMMED-FOLD-01/Focused/integration.json').read_text()))
dirs = [Path(flags[i + 1]) for i, v in enumerate(flags[:-1]) if v == '-I']
for name in ('CADCore', 'HashTreeCollections', 'InternalCollectionsUtilities'):
    for directory in dirs:
        p = directory / (name + '.swiftmodule')
        if p.is_dir():
            candidates = list(p.glob('*.swiftmodule'))
            assert len(candidates) == 1
            p = candidates[0]
        if p.is_file():
            assert sha(p) == metadata[str(p)], p
            products[str(p)] = sha(p)
            break
    else:
        raise AssertionError('Missing receipt-bound import: ' + name)
topology = json.loads((r / '.build/trimmed-fold-20261013/green-native/premises.json').read_text())['sources']
for p in (r / 'Sources/CADTopology').rglob('*.swift'):
    assert sha(p) == topology[str(p)], p
    inputs[str(p)] = sha(p)
edge_receipt = json.loads((edge / 'premises.json').read_text())
for p, h in edge_receipt['products'].items():
    assert sha(p) == h, p
    products[p] = h
products[str(canonical / 'CADTopology.swiftmodule')] = sha(canonical / 'CADTopology.swiftmodule')

paths = [r / 'Sources/CADKernel' / p for p in (
    'OriginalOffsetFeasibility/DefaultOffsetResultValidator.swift',
    'OriginalOffsetFeasibility/OffsetFeasibilityInvocation.swift',
    'OriginalOffsetFeasibility/OffsetFeasibilityLimits.swift',
    'OriginalOffsetFeasibility/OffsetExactScalarAdmission.swift',
    'OriginalOffsetFeasibility/OriginalOffsetNativeSelfContact.swift',
    'OriginalOffsetFeasibility/OriginalOffsetCoonsSelfContact.swift',
    'OriginalOffsetFeasibility/OriginalOffsetDraftedSelfContact.swift',
    'OriginalBoundaryClipping/OriginalExactFaceBoundaryIssuer.swift',
    'OriginalBoundaryClipping/OriginalExactFaceBoundaryLoops.swift',
    'DefaultBRepSewer.swift', 'BRepSewingDraft.swift')]
inputs.update({str(p): sha(p) for p in paths})
rsp = out / 'CADKernel.rsp'
rsp.write_text('\n'.join(json.dumps(str(p)) for p in paths) + '\n')
kernel_command = flags + ['-whole-module-optimization', '-enable-testing', '-emit-module',
    '-emit-module-path', str(out / 'CADKernel.swiftmodule'), '-module-name', 'CADKernel',
    '-emit-library', '-static', '@' + str(rsp), '-o', str(out / 'libCADKernel.a')]
kernel_cache = out / 'CADKernel-cache.json'
if kernel_cache.exists():
    cached = json.loads(kernel_cache.read_text())
    record = json.loads((out / 'CADKernel.json').read_text())
    assert cached['command'] == kernel_command and record['command'] == kernel_command
    assert record['exitCode'] == 0 and sha(out / 'CADKernel.log') == record['logSHA256']
    for section in ('inputs', 'products'):
        for p, h in cached[section].items():
            assert sha(p) == h, p
else:
    run(kernel_command, 'CADKernel', seconds=120)
    kernel_cache.write_text(json.dumps(dict(command=kernel_command,
        inputs={str(p): sha(p) for p in paths}, products=products | {
            str(out / 'CADKernel.swiftmodule'): sha(out / 'CADKernel.swiftmodule'),
            str(out / 'libCADKernel.a'): sha(out / 'libCADKernel.a')}), indent=2) + '\n')
for p in (out / 'CADKernel.swiftmodule', out / 'libCADKernel.a'):
    products[str(p)] = sha(p)
fixture = r / 'Tests/OriginalPublicAcceptanceVerification/DraftedSheetCallerAcceptance.swift'
inputs[str(fixture)] = sha(fixture)
inputs[str(Path(__file__).resolve())] = sha(Path(__file__).resolve())
dep_rsp = out / 'dependencies.rsp'
dep_rsp.write_text('\n'.join(json.dumps(str(p)) for p in dependencies) + '\n')
exe = out / ('Caller.wasm' if lane in ('wasm', 'embedded') else 'Caller')
libraries = [out / ('lib' + name + '.a') for name in ('CADKernel', 'CADModeling', 'CADIR', 'CADGeometry')]
libraries.append(edge / 'libCADTopology.a')
if not source_only:
    run(flags + ['-module-name', 'DraftedSheetCallerAcceptance', str(fixture)] + list(map(str, libraries))
        + ['@' + str(dep_rsp), '-o', str(exe)], 'caller-compile', seconds=240)
else:
    record = json.loads((out / 'caller-compile.json').read_text())
    assert record['exitCode'] == 0 and sha(out / 'caller-compile.log') == record['logSHA256']
products[str(exe)] = sha(exe)
for p, h in inputs.items():
    assert sha(p) == h, p
for p, h in products.items():
    assert sha(p) == h, p
runtime_base = []
if lane in ('wasm', 'embedded'):
    wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
    assert sha(wrapper) == wrapper.stem
    inputs[str(wrapper)] = sha(wrapper)
    runtime_base = ['/usr/local/bin/node', str(wrapper)]
if not source_only:
    run(runtime_base + [str(exe)] + (['caller'] if runtime_base else []), 'caller', seconds=240)
assert (out / 'caller.log').read_text().count('PASS actual drafted sheet') == 2
source_fixture = r / 'Tests/OriginalPublicAcceptanceVerification/DraftedSheetSourceAcceptance.swift'
inputs[str(source_fixture)] = sha(source_fixture)
source_exe = out / ('Source.wasm' if lane in ('wasm', 'embedded') else 'Source')
run(flags + ['-module-name', 'DraftedSheetSourceAcceptance', str(source_fixture)] + list(map(str, libraries))
    + ['@' + str(dep_rsp), '-o', str(source_exe)], 'source-compile', seconds=240)
products[str(source_exe)] = sha(source_exe)
run(runtime_base + [str(source_exe)] + (['source'] if runtime_base else []), 'source', seconds=240)
assert (out / 'source.log').read_text().count('PASS') == 2
for p, h in inputs.items():
    assert sha(p) == h, p
for p, h in products.items():
    assert sha(p) == h, p
(out / 'caller-premises.json').write_text(json.dumps(dict(inputs=inputs, products=products,
    scope='Actual PlanarExtrudeFeatureEvaluator and DefaultBRepSewer; both standalone and DefaultOffsetResultValidator branches.'), indent=2) + '\n')
