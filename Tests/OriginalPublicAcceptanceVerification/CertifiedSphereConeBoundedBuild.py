from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time,sys
r=Path.cwd();lane=sys.argv[1];base=r/'.build/sphere-cone-bounded-20261014-v2';out=base/lane;out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
module=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());run_node=next(n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=='run');exec(compile(ast.Module(body=[run_node],type_ignores=[]),'bounded-run','exec'))
e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COAXIAL-ARRAY-01'
products=json.loads((e/'products-current.json').read_text())
for p,h in products.items():assert sha(p)==h,p
previous=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-DRAFTED-SHEET-CALLER-01'
products.update(json.loads((previous/'products.json').read_text()))
for p,h in products.items():assert sha(p)==h,p
# Explicit source changes are owned by this cell; all remaining prior premises
# are checked before reuse of lower imports and objects.
owned={'Sources/CADGeometry/OriginalSourceIssuance/OriginalCertifiedSphereConeFullSnapshot.swift','Sources/CADGeometry/OriginalSourceIssuance/OriginalCertifiedSphereConeFullSnapshotProvider.swift','Sources/CADGeometry/OriginalSourceIssuance/OriginalCertifiedSphereConePhase.swift','Sources/CADGeometry/OriginalSourceIssuance/OriginalCertifiedSphereConePhaseProvider.swift','Sources/CADGeometry/OriginalSourceIssuance/OriginalCertifiedSphereConeLatitude.swift','Sources/CADGeometry/NativeExactRelations/OriginalCertifiedSphereConePlaneRelation.swift','Sources/CADGeometry/NativeExactGeometricRelations/OriginalCertifiedSphereConePublicProducer.swift'}
for p,h in json.loads((e/'source-premises-current.json').read_text()).items():
 if p not in owned:assert sha(r/p)==h,p
snapshot=base/'inputs';inputs={};paths=[]
for p in sorted((r/'Sources/CADGeometry').rglob('*.swift')):
 rel=p.relative_to(r);q=snapshot/rel;payload=p.read_bytes();h=hashlib.sha256(payload).hexdigest();inputs[str(rel)]=h
 if q.exists():assert sha(q)==h,q
 else:q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(payload)
 paths.append(str(q))
premises=base/'source-premises.json'
if premises.exists():assert json.loads(premises.read_text())==inputs
else:premises.write_text(json.dumps(inputs,indent=2)+'\n')
record=json.loads((e/lane/('public-composed-compile.json'if lane=='embedded'else'CADGeometry.json')).read_text());cmd=record['command'];flags=cmd[:cmd.index('-whole-module-optimization')]
rsp=out/'CADGeometry.rsp';rsp.write_text('\n'.join(json.dumps(p)for p in paths)+'\n')
geometry=[out/'CADGeometry.swiftmodule',out/'libCADGeometry.a']
original_fixture=r/'Tests/OriginalPublicAcceptanceVerification/CertifiedSphereConeBoundedAcceptance.swift'
fixture=base/'fixtures'/sha(original_fixture)/original_fixture.name
fixture_payload=original_fixture.read_bytes()
if fixture.exists():assert fixture.read_bytes()==fixture_payload
else:fixture.parent.mkdir(parents=True,exist_ok=True);fixture.write_bytes(fixture_payload)
if lane=='embedded':
 composed=out/fixture.name;composed.write_text(fixture.read_text().replace('import CADGeometry\n',''))
 module=out/'CADGeometry.swiftmodule';exe=out/'Public-composed.wasm'
 command=flags+['-whole-module-optimization','-emit-module','-emit-module-path',str(module),'-emit-executable','-module-name','CADGeometry','@'+str(rsp),str(composed),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)]
 run(command,'public-composed-compile',seconds=1200)
 wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
 run(['/usr/local/bin/node',str(wrapper),str(exe),'caller'],'public-runtime',seconds=180)
else:
 command=flags+['-whole-module-optimization','-enable-testing','-emit-module','-emit-module-path',str(geometry[0]),'-module-name','CADGeometry','-emit-library','-static','@'+str(rsp),'-o',str(geometry[1])]
 if len(sys.argv)>2 and sys.argv[2]=='fixture-only':
  rec=json.loads((out/'CADGeometry.json').read_text());assert rec['exitCode']==0
  for p,h in json.loads((out/'geometry-products.json').read_text()).items():assert sha(p)==h,p
 else:
  run(command,'CADGeometry',seconds=1200)
  (out/'geometry-products.json').write_text(json.dumps({str(p):sha(p)for p in geometry},indent=2)+'\n')
 flags=json.loads((e/lane/'public-compile.json').read_text())['command'];flags=flags[:flags.index('-module-name')];flags=flags[:1]+['-I',str(out)]+flags[1:]
 exe=out/('Public.wasm'if lane=='wasm'else'Public')
 command=flags+['-module-name','CertifiedSphereConeBoundedAcceptance',str(fixture),str(geometry[1]),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)]
 run(command,'public-compile',seconds=180)
 if lane=='wasm':
  wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
  runtime=['/usr/local/bin/node',str(wrapper),str(exe),'caller']
 else:runtime=[str(exe)]
 if lane in ['asan','wasm']:
  for group in ['success','0','1','2','3','4','5','6','7','8','publication-full','publication-empty']:
   selected=runtime[:-1]+[group]if lane=='wasm'else runtime+[group]
   run(selected,'runtime-'+group,seconds=180)
 else:run(runtime,'public-runtime',seconds=180)
(out/'accepted-products.json').write_text(json.dumps({str(p):sha(p)for p in ([exe,module]if lane=='embedded'else geometry+[exe])},indent=2)+'\n')
(out/'accepted-premises.json').write_text(json.dumps(dict(sources=inputs,products=products,fixtureSHA256=sha(fixture)),indent=2)+'\n')
