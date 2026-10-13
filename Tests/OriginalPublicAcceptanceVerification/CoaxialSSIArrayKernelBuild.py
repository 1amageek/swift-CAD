from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time,sys
r=Path.cwd();base=r/'.build/coaxial-ssi-array-20261014-v4';sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'bounded-run','exec'))
for lane in sys.argv[1:]:
 out=base/('kernel-embedded' if lane=='embedded' else 'kernel-direct-'+lane);out.mkdir(exist_ok=True)
 accepted=json.loads((base/lane/'accepted-premises.json').read_text())
 for p,h in accepted['products'].items():assert sha(p)==h,p
 for p,h in json.loads((base/lane/'accepted-products.json').read_text()).items():assert sha(p)==h,p
 if lane=='embedded':
  # This same-source metadata/object pair is accepted only for nongeneric graph compatibility.
  for p,h in json.loads((base/'embedded-imported/geometry-products.json').read_text()).items():assert sha(p)==h,p
  for p,h in json.loads((base/'source-premises.json').read_text()).items():assert sha(r/p)==h,p
 paths=[];sources={}
 for name in ['BooleanIntersectionGraph.swift','BooleanFaceSurfaceIntersection.swift','BooleanFacePairCandidate.swift','BooleanBoundaryContact.swift','BooleanBoundaryContactGeometry.swift']:
  p=r/'Sources/CADKernel'/name;q=out/name;payload=p.read_bytes()
  if q.exists():assert q.read_bytes()==payload
  else:q.write_bytes(payload)
  paths.append(str(q));sources[str(p.relative_to(r))]=sha(p)
 p=r/'Tests/OriginalPublicAcceptanceVerification/CoaxialSSIArrayKernelAcceptance.swift';q=out/p.name;q.write_bytes(p.read_bytes());paths.append(str(q));sources[str(p.relative_to(r))]=sha(p)
 c=json.loads((base/'embedded-imported/kernel-compile.json' if lane=='embedded' else base/lane/'public-compile.json').read_text())['command'];c=c[:c.index('-module-name')]
 topo=r/f'.build/trimmed-fold-20261013/edge-{lane}/libCADTopology.a';assert sha(topo)==accepted['products'][str(topo)]
 exe=out/('Compatibility.wasm'if lane in ['wasm','embedded']else'Compatibility')
 geometry=base/('embedded-imported'if lane=='embedded'else lane)/'libCADGeometry.a'
 run(c+['-module-name','OriginalCoaxialKernelCompatibility',*paths,str(geometry),str(topo),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)],'compile',seconds=180)
 runtime=[str(exe)]if lane not in ['wasm','embedded']else['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'),str(exe),'caller']
 run(runtime,'runtime',seconds=180)
 (out/'products.json').write_text(json.dumps({str(exe):sha(exe),str(topo):sha(topo)},indent=2)+'\n');(out/'source-premises.json').write_text(json.dumps(sources,indent=2)+'\n')
