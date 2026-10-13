"""Finish unchanged material controls on the frozen, production-matched fixture A."""
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
root = r / '.build/trimmed-fold-focused-20261014-v2' / lane
out = root / 'material-controls'
out.mkdir(exist_ok=True)
e = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-TRIMMED-FOLD-01/Focused'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
row = json.loads((e / 'fixtureA.json').read_text())[lane]
plan = json.loads((e / lane / 'fixtureA/input-plan.json').read_text())
fixture = Path(row['fixture']['source'])
assert sha(fixture) == row['fixture']['sha256']
for p, h in plan['inputs'].items():
    if '/Sources/' in p:
        assert sha(p) == h, p
for p, h in plan['products'].items():
    assert sha(p) == h, p
for module in ('CADKernel', 'CADModeling'):
    retained = json.loads((root / (module + '-premises.json')).read_text())
    for p, h in retained['inputs'].items():
        assert sha(p) == h, p
    for p, h in retained['products'].items():
        assert sha(p) == h, p
exe = Path(row['artifact'])
assert sha(exe) == row['artifactSHA256']
command = [str(exe)]
if lane in ('wasm', 'embedded'):
    wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
    assert sha(wrapper) == wrapper.stem
    command = ['/usr/local/bin/node', str(wrapper), str(exe)]
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[fn], type_ignores=[]), '<bounded-run>', 'exec'))
for mode in ('controls', 'empty'):
    assert sha(exe) == row['artifactSHA256']
    run(command + [mode], mode, seconds=600)
(out / 'premises.json').write_text(json.dumps(dict(productionInputs={p:h for p,h in plan['inputs'].items() if '/Sources/' in p},
    products=plan['products'], fixture=row['fixture'], executable=row['artifact'], executableSHA256=row['artifactSHA256'],
    modes=['controls','empty'], scope='Unchanged fixture A material methods; rejected raw caller expectation is not executed.'), indent=2) + '\n')
