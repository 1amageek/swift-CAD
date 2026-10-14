"""Verify matched immutable products and the actual public client on latest main."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time
r=Path.cwd();feature=Path(sys.argv[1]);expected=sys.argv[2]
assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()==expected
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-SPHERE-CONE-NODE-01'
sources=json.loads((e/'source-premises.json').read_text())
for p,h in sources.items():assert sha(r/p)==h,p
products=json.loads((e/'products.json').read_text())
for p,h in products.items():assert sha(p)==h,p
reused=json.loads((e/'reused-products.json').read_text())
for p,h in reused.items():assert sha(p)==h,p
protected=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/protected-before-delivery.json').read_text())
for p,h in protected.items():assert sha(p)==h,p
out=r/'.build/sphere-cone-node-20261014/delivery-native';out.mkdir(parents=True,exist_ok=True);lane='native'
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef) and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'runner','exec'))
cmd=json.loads((e/'accepted/native/public-compile.json').read_text())['command'];flags=cmd[:cmd.index('-module-name')]
fixture=r/'Tests/OriginalPublicAcceptanceVerification/SphereConeNodeSSIAcceptance.swift';q=out/fixture.name;q.write_bytes(fixture.read_bytes())
exe=out/'Public';geometry=feature/'.build/sphere-cone-node-20261014/v2/native/libCADGeometry.a'
run(flags+['-module-name','SphereConeNodeSSIAcceptance',str(q),str(geometry),'@'+str(feature/'.build/drafted-sheet-20261014/native/dependencies.rsp'),'-o',str(exe)],'public-compile',seconds=180)
run([str(exe)],'runtime',seconds=180)
for p,h in sources.items():assert sha(r/p)==h,p
for p,h in protected.items():assert sha(p)==h,p
(e/'integration.json').write_text(json.dumps(dict(status='PASS',sourceCommit=expected,sourceCount=len(sources),productCount=len(products),reusedProductCount=len(reused),protected=protected,clientSHA256=sha(exe),compile=json.loads((out/'public-compile.json').read_text()),runtime=json.loads((out/'runtime.json').read_text()),wholeSevenCompleted=1,wholeSevenTotal=7,full87Complete=False),indent=2)+'\n')
print('PASS independent main composition',len(sources),len(products),len(reused),len(protected))
