"""Verify the actual Native lifted edge classification prerequisite on one target."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time
r = Path.cwd()
lane = next((x for x in sys.argv[1:] if x in ['native','asan','wasm','embedded']), 'native')
out = r / '.build/trimmed-fold-20261013' / ('edge-' + lane)
out.mkdir(parents=True, exist_ok=True)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
e = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NONLINEAR-COLLAPSE-01'
products = json.loads((e / 'products.json').read_text())
for p, h in products.items(): assert sha(p) == h, p
sources = sorted((r / 'Sources/CADTopology').rglob('*.swift'))
checks = {str(p): sha(p) for p in sources}
fixture = r / 'Tests/OriginalPublicAcceptanceVerification/TrimmedFoldObservation.swift'
checks[str(fixture)] = sha(fixture)
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[fn], type_ignores=[]), '<bounded-run>', 'exec'))
base = r / '.build/nonlinear-collapse-20261013' / ('actual-' + lane)
link = json.loads((base / 'compile.json').read_text())['command']
command = [v for v in link if not v.endswith('.swift') and not v.startswith('@')]
i = command.index('-o'); command = command[:i] + command[i+2:]
if '-module-name' in command:
 i = command.index('-module-name'); command = command[:i] + command[i+2:]
command += ['-parse-as-library','-emit-library','-static','-emit-module','-enable-testing',
 '-module-name','CADTopology','-emit-module-path',str(out / 'CADTopology.swiftmodule')]
command += [str(p) for p in sources] + ['-o',str(out / 'libCADTopology.a')]
if lane == 'native':
 prior = r / '.build/trimmed-fold-20261013/green-native'
 receipt = json.loads((prior / 'premises.json').read_text())
 assert all(sha(p) == h for p,h in receipt['sources'].items())
 for p,h in receipt['products'].items(): assert sha(p) == h, p
 import shutil
 for name in ['CADTopology.swiftmodule','libCADTopology.a','topology.json','topology.log']:
  shutil.copy2(prior / name, out / name)
elif (out / 'libCADTopology.a').exists() and (out / 'CADTopology.swiftmodule').exists():
 record = json.loads((out / 'topology.json').read_text())
 assert record['exitCode'] == 0 and record['command'] == command
 assert sha(out / 'topology.log') == record['logSHA256']
 # All target builds consumed this immutable production snapshot; fixture-only changes reuse it.
 prior = json.loads((r / '.build/trimmed-fold-20261013/green-native/premises.json').read_text())
 for p,h in prior['sources'].items(): assert checks[p] == h,p
else:
 run(command,'topology',seconds=120 if lane != 'embedded' else 300)
link = [v for v in link if not v.endswith('.swift')]
if '-module-name' in link:
 link[link.index('-module-name')+1] = 'TrimmedFoldEdgeAcceptance'
else: link += ['-module-name','TrimmedFoldEdgeAcceptance']
link.insert(next(i for i,v in enumerate(link) if v.startswith('@')),str(fixture))
link += ['-I',str(out),str(out / 'libCADTopology.a')]
exe = out / ('Proof.wasm' if lane in ['wasm','embedded'] else 'Proof')
link[link.index('-o')+1] = str(exe)
response = Path(next(v[1:] for v in link if v.startswith('@')))
for line in response.read_text().splitlines():
 if line:
  p = json.loads(line); checks[p] = sha(p)
run(link,'compile',seconds=120 if lane != 'embedded' else 300)
runtime = [str(exe)]
if lane in ['wasm','embedded']:
 wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
 assert sha(wrapper) == wrapper.stem
 runtime = ['/usr/local/bin/node',str(wrapper),str(exe),'actual']
 checks[str(wrapper)] = sha(wrapper)
run(runtime,'acceptance')
for p,h in checks.items(): assert sha(p) == h,p
for p,h in products.items(): assert sha(p) == h,p
new = {str(p):sha(p) for p in [out / 'CADTopology.swiftmodule',out / 'libCADTopology.a',exe]}
(out / 'premises.json').write_text(json.dumps(dict(checks=checks,products=new,
 scope='Actual exact folded face/Native lift endpoint classification; full material self-contact and offset validator not yet connected.'),indent=2)+'\n')
