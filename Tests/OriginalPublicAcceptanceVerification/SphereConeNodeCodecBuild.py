from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time,sys
r=Path.cwd();lane=sys.argv[1];base=r/'.build/sphere-cone-node-cs-20261014/v3';g=base/('embedded-portable'if lane=='embedded'else lane);out=base/'codec'/lane;out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for p,h in json.loads((g/'accepted-products.json').read_text()).items():assert sha(p)==h,p
products=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-CERT-SPHERECONE-FULL-01/reused-products.json').read_text())
for p,h in products.items():assert sha(p)==h,p
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'runner','exec'))
sources={};paths=[]
# Compile the actual Geometry/Topology writer closure, not unrelated document APIs.
selected=[p for p in sorted((r/'Sources/CADIR/PortableSourceEncoding').glob('*.swift')) if '"CADGeometry.'in p.read_text() or '"CADTopology.'in p.read_text() or 'extension OriginalNormalizedAffineSource.Family'in p.read_text()]
for p in selected:
 rel=p.relative_to(r);q=base/'codec-inputs'/rel;h=sha(p);sources[str(rel)]=h
 if q.exists():assert sha(q)==h,q
 else:q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(p.read_bytes())
 paths.append(str(q))
(out/'source-premises.json').write_text(json.dumps(sources,indent=2)+'\n')
rsp=out/'CADIR.rsp';rsp.write_text('\n'.join(json.dumps(p)for p in paths)+'\n')
old=json.loads((r/f'.build/drafted-sheet-20261014/{lane}/CADIR.json').read_text())['command'];flags=old[:old.index('-whole-module-optimization')];flags=flags[:1]+['-I',str(g),'-I',str(out)]+flags[1:]
module=out/'CADIR.swiftmodule';lib=out/'libCADIR.a'
run(flags+['-whole-module-optimization','-emit-module','-emit-module-path',str(module),'-module-name','CADIR','-emit-library','-static','@'+str(rsp),'-o',str(lib)],'CADIR',seconds=1200)
f=r/'Tests/OriginalPublicAcceptanceVerification/SphereConeNodeCodecAcceptance.swift';fixture=out/f.name;fixture.write_bytes(f.read_bytes())
exe=out/('Public.wasm'if lane in ['wasm','embedded']else'Public')
# Only the existing Topology object is added; no lower target is regenerated.
topo=r/f'.build/trimmed-fold-20261013/edge-{lane}/libCADTopology.a'
if not topo.exists():
 topo=r/f'.build/trimmed-fold-20261013/edge-{lane}/CADTopology.o'
assert topo.exists(),topo
assert str(topo) in products,topo
cg=[str(g/'libCADGeometry.a')]if lane!='embedded'else[]
run(flags+(['-whole-module-optimization']if lane=='embedded'else[])+['-module-name','SphereConeNodeCodecAcceptance',str(fixture),str(lib),*cg,str(topo),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)],'codec-compile',seconds=180)
wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
run(['/usr/local/bin/node',str(wrapper),str(exe),'all']if lane in ['wasm','embedded']else[str(exe)],'codec-runtime',seconds=180)
(out/'accepted-products.json').write_text(json.dumps({str(p):sha(p)for p in [module,lib,exe]},indent=2)+'\n')
(out/'accepted-premises.json').write_text(json.dumps(dict(sources=sources,products=products,geometry={p:h for p,h in json.loads((g/'accepted-products.json').read_text()).items() if Path(p).name != 'Public' and Path(p).name != 'Public.wasm'},fixtureSHA256=sha(f)),indent=2)+'\n')
