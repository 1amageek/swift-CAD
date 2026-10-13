"""Generate only the explicitly authorized fixed Geometry caller snapshot."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time
r=Path.cwd(); lane=sys.argv[1]; out=r/'.build/embedding-caller-v2-20261014'/lane
plan=json.loads((out/'plan.json').read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for p,h in plan['inputs'].items():assert sha(p)==h,p
tree=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
fn=next(node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name=='run')
exec(compile(ast.Module(body=[fn],type_ignores=[]),'<bounded-run>','exec'))
run(plan['command'],'CADGeometry',seconds=plan['maximumSeconds'])
for p,h in plan['inputs'].items():assert sha(p)==h,p
products={str(p):sha(p) for p in (out/'CADGeometry.swiftmodule',out/'libCADGeometry.a')}
(out/'premises.json').write_text(json.dumps(dict(inputs=plan['inputs'],products=products,
    recordSHA256=sha(out/'CADGeometry.json'),scope=plan['scope']),indent=2)+'\n')
print(lane,'fixed Geometry generation PASS',flush=True)
