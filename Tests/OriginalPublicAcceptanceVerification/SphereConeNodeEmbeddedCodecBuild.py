from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time
r=Path.cwd();lane='embedded';base=r/'.build/sphere-cone-node-cs-20261014/v3';g=base/'embedded-portable';out=base/'codec/embedded-composed';out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
products=json.loads((g/'accepted-products.json').read_text());products.update(json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-CERT-SPHERECONE-FULL-01/reused-products.json').read_text()))
for p,h in products.items():assert sha(p)==h,p
sources=json.loads((base/'source-premises.json').read_text())
for p,h in sources.items():assert sha(r/p)==h,p
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'runner','exec'))
paths=[str(base/'inputs'/p)for p in sources];writers={};composed={}
for p in sorted((r/'Sources/CADIR/PortableSourceEncoding').glob('*.swift')):
 text=p.read_text()
 if not ('"CADGeometry.'in text or 'extension OriginalNormalizedAffineSource.Family'in text):continue
 q=out/'writers'/p.name;q.parent.mkdir(exist_ok=True);q.write_text(text.replace('import CADGeometry\n','').replace('import CADTopology\n',''))
 paths.append(str(q));writers[str(p.relative_to(r))]=sha(p);composed[str(q)]=sha(q)
f=r/'Tests/OriginalPublicAcceptanceVerification/SphereConeNodeCodecAcceptance.swift';fixture=out/f.name
fixture.write_text(f.read_text().replace('import CADGeometry\n','').replace('import CADIR\n',''));paths.append(str(fixture));composed[str(fixture)]=sha(fixture)
rsp=out/'sources.rsp';rsp.write_text('\n'.join(json.dumps(p)for p in paths)+'\n')
command=json.loads((g/'public-composed-compile.json').read_text())['command'];flags=command[:command.index('-whole-module-optimization')]
topo=r/'.build/trimmed-fold-20261013/edge-embedded/libCADTopology.a';assert sha(topo)==products[str(topo)]
exe=out/'Public.wasm'
# This verifies identical writer bodies; the recorded cross-module reader failure remains open.
run(flags+['-whole-module-optimization','-module-name','CADGeometry','-emit-executable','@'+str(rsp),'@'+str(r/'.build/drafted-sheet-20261014/embedded/dependencies.rsp'),'-o',str(exe)],'codec-composed-compile',seconds=1200)
wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
run(['/usr/local/bin/node',str(wrapper),str(exe),'all'],'codec-runtime',seconds=180)
(out/'accepted-products.json').write_text(json.dumps({str(exe):sha(exe)},indent=2)+'\n')
(out/'accepted-premises.json').write_text(json.dumps(dict(sources=sources,writers=writers,composed=composed,reusedProducts=products,fixtureSHA256=sha(f),scope='Identical source-body composition; does not accept the recorded separate-module reader failure.'),indent=2)+'\n')
