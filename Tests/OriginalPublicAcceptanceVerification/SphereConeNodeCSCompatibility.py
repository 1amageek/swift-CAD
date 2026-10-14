from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time
r=Path.cwd();lane='native';base=r/'.build/sphere-cone-node-cs-20261014/v4';out=base/'compatibility-native';out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'runner','exec'))
products=json.loads((base/lane/'geometry-products.json').read_text());products.update(json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-CERT-SPHERECONE-FULL-01/reused-products.json').read_text()))
for p,h in products.items():assert sha(p)==h,p
flags=json.loads((base/lane/'public-compile.json').read_text())['command'];flags=flags[:flags.index('-module-name')]
inputs={};artifacts={}
for name,groups in [('CertifiedSphereConeFullAcceptance',['success']),('SphereConeNodeSSIAcceptance',['success','endpoints','prepared'])]:
 p=r/'Tests/OriginalPublicAcceptanceVerification'/(name+'.swift');q=out/p.name;q.write_bytes(p.read_bytes());inputs[str(p.relative_to(r))]=sha(p)
 exe=out/name;run(flags+['-module-name',name,str(q),str(base/lane/'libCADGeometry.a'),'@'+str(r/'.build/drafted-sheet-20261014/native/dependencies.rsp'),'-o',str(exe)],name+'-compile',seconds=180)
 for group in groups:run([str(exe),group],name+'-'+group,seconds=180)
 artifacts[str(exe)]=sha(exe)
(out/'accepted.json').write_text(json.dumps(dict(sources=inputs,reusedProducts=products,products=artifacts),indent=2)+'\n')
