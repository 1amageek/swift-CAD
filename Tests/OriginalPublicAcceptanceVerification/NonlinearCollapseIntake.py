"""Compile actual changed intake bodies independently of the retained CAD module."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time
r = Path.cwd()
lane = next((v for v in sys.argv[1:] if v in ['native','asan','wasm','embedded']), 'native')
actual = '--actual' in sys.argv
assert lane != 'embedded' or not actual, 'Embedded legacy validator replacement requires its own current WMO receipt.'
out = r / '.build/nonlinear-collapse-20261013' / (('actual-' if actual else 'intake-') + lane)
out.mkdir(parents=True, exist_ok=True)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
e = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-IMAGE-PERIOD-01'
baseline = json.loads((e / 'source-premises.json').read_text())
products = json.loads((e / 'products.json').read_text())
changed = {
    'Sources/CADGeometry/SurfaceParameterCurve.swift',
    'Sources/CADGeometry/OriginalGeometrySourceValidation/SurfaceParameterCurve+BoundedValidation.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/OriginalNativeSurfaceLiftSnapshotProvider.swift',
}
for p, h in baseline.items():
    if p not in changed: assert sha(r / p) == h, p
for p, h in products.items(): assert sha(p) == h, p
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[function], type_ignores=[]), '<bounded-run>', 'exec'))
inputs = []
production_inputs = {str(r / p): sha(r / p) for p in changed}
for relative in [
    'Sources/CADGeometry/OriginalGeometrySourceValidation/OriginalQuadraticPcurveContainment.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/OriginalPolynomialNativeLiftChart.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/OriginalPolynomialNativeLiftChartIssuing.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalPolynomialNativeLiftChartIssuer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/OriginalNativeSurfaceLiftCurveSnapshotProvider.swift',
]+([] if actual else ['Sources/CADGeometry/OriginalSourceIssuance/OriginalNativeSurfaceLiftSnapshotProvider.swift']):
    path = r / relative
    production_inputs[str(path)] = sha(path)
    port = out / path.name
    port.write_text('@testable import CADGeometry\n' + path.read_text())
    inputs.append(str(port))
fixture = r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseIntake.swift'
base = r / '.build/native-identity-current-20261013-v2' / lane / 'compile.json'
command = [v for v in json.loads(base.read_text())['command'] if not v.endswith('.swift')]
if actual:
    receipt = r / '.build/native-identity-current-20261013-v2' / lane / 'fresh-issuer.json'
    prefix = json.loads(receipt.read_text())['command']
    prefix = prefix[:prefix.index('-primary-file')]
    helper = 'Sources/CADGeometry/OriginalGeometrySourceValidation/OriginalQuadraticPcurveContainment.swift'
    primaries = sorted(changed | {helper})
    all_sources = sorted(str(r / p) for p in baseline if p.startswith('Sources/CADGeometry/')) + [str(r / helper)]
    response = Path(next(v[1:] for v in command if v.startswith('@')))
    objects = [Path(json.loads(line)) for line in response.read_text().splitlines() if line]
    for relative in primaries:
        path = r / relative
        others = out / (path.stem + '.rsp')
        others.write_text('\n'.join(json.dumps(p) for p in all_sources if p != str(path)) + '\n')
        obj = out / (path.stem + '.o')
        current = {p: sha(p) for p in all_sources}
        manifest = out / (path.stem + '-inputs.json')
        if not manifest.exists() or json.loads(manifest.read_text()) != current or not obj.exists():
            run(prefix + ['-primary-file', str(path), '@' + str(others), '-o', str(obj)], path.stem)
            manifest.write_text(json.dumps(current, indent=2) + '\n')
        else:
            record = json.loads((out / (path.stem + '.json')).read_text())
            assert record['exitCode'] == 0 and record.get('objectSHA256') == sha(obj), path
        record_path = out / (path.stem + '.json')
        record = json.loads(record_path.read_text())
        record['objectSHA256'] = sha(obj)
        record_path.write_text(json.dumps(record, indent=2) + '\n')
        replaced = [p for p in objects if p.stem in [path.stem, path.name]]
        assert len(replaced) == (0 if relative == helper else 1), (path, replaced)
        objects = [p for p in objects if p not in replaced] + [obj]
    response = out / 'objects.rsp'
    response.write_text('\n'.join(json.dumps(str(p)) for p in objects) + '\n')
    command = ['@' + str(response) if v.startswith('@') else v for v in command]
offset = next(i for i, v in enumerate(command) if v.startswith('@'))
command[offset:offset] = inputs + [str(fixture)]
exe = out / ('Proof.wasm' if lane in ['wasm','embedded'] else 'Proof')
command[-1] = str(exe)
run(command, 'compile', seconds=1200 if lane == 'embedded' else 120)
runtime = [str(exe)]
if lane in ['wasm','embedded']:
    wasi = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
    assert sha(wasi) == wasi.stem
    runtime = ['/usr/local/bin/node', str(wasi), str(exe), 'actual' if actual else 'intake']
run(runtime, 'intake', env=dict(os.environ, CAD_PROOF_GROUP='actual' if actual else 'intake'))
for p, h in production_inputs.items(): assert sha(p) == h, p
for p, h in products.items(): assert sha(p) == h, p
(out / 'premises.json').write_text(json.dumps(dict(
    source=production_inputs,
    ports={p: sha(p) for p in inputs}, fixtureSHA256=sha(fixture),
    productManifestSHA256=sha(e / 'products.json'), executableSHA256=sha(exe),
    scope=('Fresh current legacy/bounded validation bodies and source provider; new lift/ruled issuer bodies independently compiled.'
        if actual else 'Actual source provider and nonlinear/ruled/identity/consumer/public-result bodies; cached legacy validation body is not tested by this port.')
), indent=2) + '\n')
