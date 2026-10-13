"""Prepare current Geometry WMO verification; execution requires the explicit scope exception."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time
r = Path.cwd()
lane = 'embedded'
out = r / '.build/nonlinear-collapse-20261013/actual-embedded'
out.mkdir(parents=True, exist_ok=True)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
base = r / '.build/periodic-offset-cs-20261013/embedded'
source_paths = sorted((r / 'Sources/CADGeometry').rglob('*.swift'))
inputs = {str(p): sha(p) for p in source_paths}
assert len(inputs) == 2049
e = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-IMAGE-PERIOD-01'
products = json.loads((e / 'products.json').read_text())
for p, h in products.items(): assert sha(p) == h, p
external_path = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/audit.json'
external = json.loads(external_path.read_text())['externalProducts']
for p, h in external.items(): assert sha(p) == h, p
sources_rsp = out / 'sources.rsp'
sources_rsp.write_text('\n'.join(json.dumps(str(p)) for p in source_paths) + '\n')
sources_list = out / 'sources.list'
sources_list.write_text('\n'.join(str(p) for p in source_paths) + '\n')
objects = [out / 'owner-objects' / p.relative_to(r / 'Sources/CADGeometry').with_suffix('.o') for p in source_paths]
for p in objects: p.parent.mkdir(parents=True, exist_ok=True)
outputs = out / 'outputs.list'
outputs.write_text('\n'.join(str(p) for p in objects) + '\n')
supplementary = out / 'supplementary.json'
supplementary.write_text(json.dumps({str(p): {} for p in source_paths}, indent=2) + '\n')
module = list(json.loads((base / 'module.json').read_text())['command'])
module = ['@' + str(sources_rsp) if v.startswith('@') else v for v in module]
module[module.index('-o') + 1] = str(out / 'CADGeometry.swiftmodule')
object_command = list(json.loads((base / 'objects.json').read_text())['command'])
for option, value in [('-filelist', sources_list), ('-output-filelist', outputs),
                      ('-supplementary-output-file-map', supplementary)]:
    object_command[object_command.index(option) + 1] = str(value)
for command in [module, object_command]:
    command[command.index('-module-cache-path') + 1] = str(out / 'cache')
plan = dict(sourceCount=len(inputs), sources=inputs, moduleCommand=module,
    objectCommand=object_command, geometryWallLimitSeconds=1200,
    rssLimitBytes=10737418240, sdkIdentifier='swift-6.4.0-RELEASE_wasm-embedded',
    baseProductManifestSHA256=sha(e / 'products.json'), externalManifestSHA256=sha(external_path),
    scope='Current Geometry module and WMO objects; reuse Core/collections and independent L2-L6 artifacts; Kernel is not rebuilt.')
(out / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
if '--execute' not in sys.argv:
    print('Prepared current Geometry WMO plan:', len(inputs), 'Swift inputs; no compiler executed.')
    raise SystemExit(0)
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[function], type_ignores=[]), '<bounded-run>', 'exec'))
deadline = time.monotonic() + 1200
run(module, 'module', seconds=max(1, deadline - time.monotonic()))
run(object_command, 'objects', seconds=max(1, deadline - time.monotonic()))
for p, h in inputs.items(): assert sha(p) == h, p
for p, h in products.items(): assert sha(p) == h, p
for p, h in external.items(): assert sha(p) == h, p
current = r / '.build/native-identity-current-20261013-v2/embedded'
command = [v for v in json.loads((current / 'compile.json').read_text())['command'] if not v.endswith('.swift')]
prior_rsp = Path(next(v[1:] for v in command if v.startswith('@')))
dependencies = [Path(json.loads(line)) for line in prior_rsp.read_text().splitlines() if line]
dependencies = [p for p in dependencies if any('/' + target + '.objlib/' in str(p)
    for target in ['CADCore', 'HashTreeCollections', 'InternalCollectionsUtilities'])]
assert dependencies and any('/CADCore.objlib/' in str(p) for p in dependencies)
link_rsp = out / 'link.rsp'
link_rsp.write_text('\n'.join(json.dumps(str(p)) for p in objects + dependencies) + '\n')
command = ['@' + str(link_rsp) if v.startswith('@') else v for v in command]
command[command.index('-module-name') + 1] = 'NonlinearCollapseActualEmbedded'
command[command.index('-module-cache-path') + 1] = str(out / 'cache')
command[command.index('-I'):command.index('-I')] = ['-I', str(out)]
fixture = r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseIntake.swift'
command.insert(next(i for i, v in enumerate(command) if v.startswith('@')), str(fixture))
executable = out / 'Proof.wasm'
command[-1] = str(executable)
run(command, 'compile', seconds=1200)
wasi = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
assert sha(wasi) == wasi.stem
run(['/usr/local/bin/node', str(wasi), str(executable), 'actual'], 'intake')
checks = {str(p): sha(p) for p in objects + dependencies + [out / 'CADGeometry.swiftmodule', fixture, executable, wasi]}
(out / 'premises.json').write_text(json.dumps(dict(inputs=inputs, checks=checks,
    planSHA256=sha(out / 'plan.json'), scope='Actual current Geometry module, legacy/bounded validators and source/DI/identity/consumer/public geometric result.'), indent=2) + '\n')
for p, h in inputs.items(): assert sha(p) == h, p
