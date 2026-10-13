from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time,sys,shlex
r=Path.cwd();lane=sys.argv[1];base=r/'.build/certified-coaxial-public-20261014-v2';out=base/lane;out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
module=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
run_node=next(n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=='run')
exec(compile(ast.Module(body=[run_node],type_ignores=[]),'bounded-run','exec'))
e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-DRAFTED-SHEET-CALLER-01'
products=json.loads((e/'products.json').read_text())
for p,h in products.items():assert sha(p)==h,p
old_sources=json.loads((e/'source-premises.json').read_text())
changed={'Sources/CADGeometry/DefaultCurveSurfaceIntersector.swift','Sources/CADGeometry/CurveSurfaceOverlap/DefaultCurveSurfaceIntersector+Overlap.swift','Sources/CADGeometry/CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift'}
for p,h in old_sources.items():
 if p not in changed:assert sha(r/p)==h,p
inputs={}
snapshot=base/'inputs'
paths=[]
for p in sorted((r/'Sources/CADGeometry').rglob('*.swift')):
 rel=p.relative_to(r);q=snapshot/rel;q.parent.mkdir(parents=True,exist_ok=True)
 payload=p.read_bytes();h=hashlib.sha256(payload).hexdigest();inputs[str(rel)]=h
 if q.exists():assert sha(q)==h,q
 else:q.write_bytes(payload)
 paths.append(str(q))
premises=base/'source-premises.json'
if premises.exists():assert json.loads(premises.read_text())==inputs
else:premises.write_text(json.dumps(inputs,indent=2)+'\n')
record=json.loads((r/f'.build/drafted-sheet-20261014/{lane}/CADGeometry.json').read_text())
cmd=record['command'];flags=cmd[:cmd.index('-whole-module-optimization')]
if lane=='embedded':flags[flags.index('-num-threads')+1]='1'
rsp=out/'CADGeometry.rsp';rsp.write_text('\n'.join(json.dumps(p) for p in paths)+'\n')
command=flags+['-whole-module-optimization','-enable-testing','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'-module-name','CADGeometry','-emit-library','-static','@'+str(rsp),'-o',str(out/'libCADGeometry.a')]
geometry_products=out/'geometry-products.json'
if len(sys.argv)>2 and sys.argv[2]=='fixture-only':
 record=json.loads((out/('CADGeometry-thread1.json'if lane=='embedded'else'CADGeometry.json')).read_text());assert record['exitCode']==0
 assert sha(out/('CADGeometry-thread1.log'if lane=='embedded'else'CADGeometry.log'))==record['logSHA256']
 for p,h in json.loads(geometry_products.read_text()).items():assert sha(p)==h,p
else:
 run(command,'CADGeometry-thread1'if lane=='embedded'else'CADGeometry',seconds=1200)
 geometry_products.write_text(json.dumps({str(p):sha(p)for p in [out/'CADGeometry.swiftmodule',out/'libCADGeometry.a']},indent=2)+'\n')
fixture=r/'Tests/OriginalPublicAcceptanceVerification/CertifiedCoaxialPublicAcceptance.swift'
prior=json.loads((r/f'.build/drafted-sheet-20261014/{lane}/caller-compile.json').read_text())['command']
flags=prior[:prior.index('-module-name')];flags=flags[:1]+['-I',str(out)]+flags[1:]
if lane=='embedded':flags[flags.index('-num-threads')+1]='1'
exe=out/('Public.wasm'if lane in ['wasm','embedded']else'Public')
command=flags+['-module-name','CertifiedCoaxialPublicAcceptance',str(fixture),str(out/'libCADGeometry.a'),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)]
if lane=='embedded':command=command[:1]+['-whole-module-optimization']+command[1:]
run(command,'public-compile',seconds=180)
if lane in ['wasm','embedded']:
 wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
 runtime=['/usr/local/bin/node',str(wrapper),str(exe),'caller']
else:runtime=[str(exe)]
run(runtime,'public-runtime',seconds=180)
(out/'accepted-products.json').write_text(json.dumps({str(p):sha(p)for p in [out/'CADGeometry.swiftmodule',out/'libCADGeometry.a',exe]},indent=2)+'\n')
(out/'accepted-premises.json').write_text(json.dumps(dict(sources=inputs,products=products,fixtureSHA256=sha(fixture)),indent=2)+'\n')
