from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time
r=Path.cwd();base=r/'.build/coaxial-ssi-array-20261014-v4';out=base/'embedded-module-osize';lane='embedded'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
n=next(n for n in ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'bounded-run','exec'))
for p,h in json.loads((out/'products.json').read_text()).items():assert sha(p)==h,p
assert (out/'CADGeometry.swiftmodule').stat().st_size < 268435456
for name,prior in [('minimal-typecheck',base/'embedded-import-diagnostic/minimal-module-only-typecheck.json'),('kernel-primary-typecheck',base/'kernel-primary-embedded/typecheck-frontend.json')]:
 c=json.loads(prior.read_text())['command'];c=[str(out) if v in [str(base/'embedded'),str(base/'embedded-module-only')] else v for v in c]
 run(c,name,seconds=180)
