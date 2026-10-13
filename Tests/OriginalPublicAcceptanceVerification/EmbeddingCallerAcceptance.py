"""Run the real embedding caller against receipt-bound production modules."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time

r = Path.cwd()
lane = sys.argv[1]
assert lane in ('native', 'asan', 'wasm', 'embedded')
geometry = r / '.build/embedding-caller-v2-20261014' / lane
edge = r / '.build/trimmed-fold-20261013' / ('edge-' + lane)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
fixture = r / 'Tests/OriginalPublicAcceptanceVerification/EmbeddingCallerAcceptance.swift'
out = geometry / ('caller-' + sha(fixture)[:16])
out.mkdir(exist_ok=True)
premises = json.loads((geometry / 'premises.json').read_text())
record = json.loads((geometry / 'CADGeometry.json').read_text())
assert record['exitCode'] == 0 and record['stopReason'] is None
assert sha(geometry / 'CADGeometry.json') == premises['recordSHA256']
assert sha(geometry / 'CADGeometry.log') == record['logSHA256']
inputs = dict(premises['inputs'])
products = dict(premises['products'])
for p, h in inputs.items(): assert sha(p) == h, p
for p, h in products.items(): assert sha(p) == h, p

base = json.loads((edge / 'compile.json').read_text())['command']
flags = [v for v in base if not v.endswith('.swift') and not v.startswith('@') and not v.endswith('.a')]
for option in ('-o', '-module-name'):
    if option in flags:
        i = flags.index(option)
        del flags[i:i + 2]
flags[flags.index('-package-name') + 1] = 'nativeexactrelationverification'
flags[1:1] = ['-I', str(geometry)]
prior = Path(next(v[1:] for v in base if v.startswith('@')))
dependencies = [Path(json.loads(v)) for v in prior.read_text().splitlines() if v]
dependencies = [p for p in dependencies if any(t in str(p) for t in (
    '/CADCore-t.build/', '/CADCore.objlib/', '/HashTreeCollections-t.build/', '/HashTreeCollections.objlib/',
    '/InternalCollectionsUtilities-t.build/', '/InternalCollectionsUtilities.objlib/'))
    or p.name in ('CADCore.o', 'HashTreeCollections.o', 'InternalCollectionsUtilities.o')]
assert dependencies
authority = json.loads((r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NONLINEAR-COLLAPSE-01/products.json').read_text())
for p in dependencies:
    assert sha(p) == authority[str(p)], p
    products[str(p)] = sha(p)

# Metadata used by both module generation and fixture compilation is a separate premise.
metadata = {}
def collect(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key.startswith('/') and isinstance(item, str) and len(item) == 64:
                metadata[key] = item
            else: collect(item)
    elif isinstance(value, list):
        for item in value: collect(item)
collect(json.loads((r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-TRIMMED-FOLD-01/Focused/integration.json').read_text()))
for command in (record['command'], flags):
    dirs = [Path(command[i + 1]) for i, v in enumerate(command[:-1]) if v == '-I']
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
        else: raise AssertionError('Missing receipt-bound import: ' + name)

frozen = out / ('Fixture-' + sha(fixture) + '.swift')
frozen.write_bytes(fixture.read_bytes())
for p in (fixture, frozen, Path(__file__).resolve()): inputs[str(p)] = sha(p)
rsp = out / 'dependencies.rsp'
rsp.write_text('\n'.join(json.dumps(str(p)) for p in dependencies) + '\n')
exe = out / ('Proof.wasm' if lane in ('wasm', 'embedded') else 'Proof')
command = flags + ['-module-name', 'EmbeddingCallerAcceptance', str(frozen),
    str(geometry / 'libCADGeometry.a'), '@' + str(rsp), '-o', str(exe)]
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[fn], type_ignores=[]), '<bounded-run>', 'exec'))
cache = out / 'compile-premises.json'
if cache.exists():
    cached = json.loads(cache.read_text())
    compiled = json.loads((out / 'fixture.json').read_text())
    assert compiled['command'] == command and compiled['exitCode'] == 0
    assert sha(out / 'fixture.log') == compiled['logSHA256']
    for p, h in cached['inputs'].items(): assert sha(p) == h, p
    for p, h in cached['products'].items(): assert sha(p) == h, p
else:
    run(command, 'fixture', seconds=240)
    cache.write_text(json.dumps(dict(inputs=inputs, products=products | {str(exe): sha(exe)}), indent=2) + '\n')
products[str(exe)] = sha(exe)
runtime = [str(exe)]
if lane in ('wasm', 'embedded'):
    wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
    assert sha(wrapper) == wrapper.stem
    inputs[str(wrapper)] = sha(wrapper)
    runtime = ['/usr/local/bin/node', str(wrapper), str(exe)]
modes = sys.argv[2:] or ['caller']
for mode in modes:
    for p, h in inputs.items(): assert sha(p) == h, p
    for p, h in products.items(): assert sha(p) == h, p
    os.environ['CAD_PROOF_GROUP'] = mode
    run(runtime + ([mode] if lane in ('wasm', 'embedded') else []), mode, seconds=240)
    assert 'PASS' in (out / (mode + '.log')).read_text()
(out / 'premises.json').write_text(json.dumps(dict(inputs=inputs, products=products, modes=modes,
    scope='Actual production DefaultOriginalSurfaceEmbeddingValidator; unchanged Core reused.'), indent=2) + '\n')
