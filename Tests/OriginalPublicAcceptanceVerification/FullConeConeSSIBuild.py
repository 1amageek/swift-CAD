from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time,sys
r=Path.cwd();lane=sys.argv[1];base=r/'.build/full-cone-cone-ssi-20261014/v1';out=base/('embedded-portable' if lane=='embedded' else lane);out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-CERT-SPHERECONE-FULL-01'
products=json.loads((e/'reused-products.json').read_text())
for p,h in products.items():assert sha(p)==h,p
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'runner','exec'))
snapshot=base/'inputs';sources={};paths=[]
for p in sorted((r/'Sources/CADGeometry').rglob('*.swift')):
 rel=p.relative_to(r);q=snapshot/rel;data=p.read_bytes();h=hashlib.sha256(data).hexdigest();sources[str(rel)]=h
 if q.exists():assert sha(q)==h,q
 else:q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(data)
 paths.append(str(q))
premises=base/'source-premises.json'
if premises.exists():assert json.loads(premises.read_text())==sources
else:premises.write_text(json.dumps(sources,indent=2)+'\n')
rsp=out/'CADGeometry.rsp';rsp.write_text('\n'.join(json.dumps(p)for p in paths)+'\n')
previous=r/'.build/full-sphere-cone-ssi-20261014/v2'/('embedded-portable' if lane=='embedded' else lane)
record=json.loads((previous/('public-composed-compile.json'if lane=='embedded'else'CADGeometry.json')).read_text());cmd=record['command'];flags=cmd[:cmd.index('-whole-module-optimization')]
f=r/'Tests/OriginalPublicAcceptanceVerification/FullConeConeSSIAcceptance.swift';fixture=base/'fixtures'/sha(f)/f.name
if fixture.exists():assert fixture.read_bytes()==f.read_bytes()
else:fixture.parent.mkdir(parents=True,exist_ok=True);fixture.write_bytes(f.read_bytes())
geometry=[out/'CADGeometry.swiftmodule',out/'libCADGeometry.a']
if lane=='embedded':
 composed=out/fixture.name;composed.write_text(fixture.read_text().replace('import CADGeometry\n',''))
 exe=out/'Public.wasm';command=flags+['-whole-module-optimization','-emit-module','-emit-module-path',str(geometry[0]),'-emit-executable','-module-name','CADGeometry','@'+str(rsp),str(composed),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)]
 run(command,'public-composed-compile',seconds=1200)
else:
 command=flags+['-whole-module-optimization','-enable-testing','-emit-module','-emit-module-path',str(geometry[0]),'-module-name','CADGeometry','-emit-library','-static','@'+str(rsp),'-o',str(geometry[1])]
 if len(sys.argv)>2 and sys.argv[2]=='fixture-only':
  for p,h in json.loads((out/'geometry-products.json').read_text()).items():assert sha(p)==h,p
 else:
  run(command,'CADGeometry',seconds=1200);(out/'geometry-products.json').write_text(json.dumps({str(p):sha(p)for p in geometry},indent=2)+'\n')
 c=json.loads((previous/'public-compile.json').read_text())['command'];flags=c[:c.index('-module-name')];flags=flags[:1]+['-I',str(out)]+flags[1:]
 exe=out/('Public.wasm'if lane=='wasm'else'Public')
 run(flags+['-module-name','FullConeConeSSIAcceptance',str(fixture),str(geometry[1]),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)],'public-compile',seconds=180)
wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
groups=sys.argv[3:] if len(sys.argv)>3 else (['success','endpoints','publication','prepared','terminal'] if lane=='native' else ['success-0','success-1','success-2','success-3','endpoints','publication','prepared','terminal'])
for group in groups:
 run(['/usr/local/bin/node',str(wrapper),str(exe),group]if lane in ['wasm','embedded']else[str(exe),group],'runtime-'+group,seconds=180)
assert all(group in ['success','success-0','success-1','success-2','success-3','endpoints','publication','prepared','terminal'] for group in groups)
(out/'accepted-products.json').write_text(json.dumps({str(p):sha(p)for p in ([exe,geometry[0]]if lane=='embedded'else geometry+[exe])},indent=2)+'\n')
(out/'accepted-premises.json').write_text(json.dumps(dict(sources=sources,products=products,fixtureSHA256=sha(fixture)),indent=2)+'\n')
