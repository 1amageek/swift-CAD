from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time,sys
r=Path.cwd();base=r/'.build/coaxial-ssi-array-20261014-v4';sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'bounded-run','exec'))
for lane in sys.argv[1:]:
 out=base/lane
 for p,h in json.loads((out/'accepted-products.json').read_text()).items():assert sha(p)==h,p
 for p,h in json.loads((base/'source-premises.json').read_text()).items():assert sha(r/p)==h,p
 products={}
 for name,fixture in [('coaxial',r/'Tests/OriginalPublicAcceptanceVerification/CertifiedCoaxialPublicAcceptance.swift'),('pairlift',r/'Tests/OriginalPublicAcceptanceVerification/CertifiedPairLiftAcceptance.swift')]:
  frozen=base/'inputs'/fixture.relative_to(r);frozen.parent.mkdir(parents=True,exist_ok=True)
  if frozen.exists():assert frozen.read_bytes()==fixture.read_bytes()
  else:frozen.write_bytes(fixture.read_bytes())
  c=json.loads((out/'public-compile.json').read_text())['command'];c=c[:c.index('-module-name')];exe=out/(name+'-regression'+('.wasm'if lane=='wasm'else''))
  run(c+['-module-name','CertifiedPublicRegression',str(frozen),str(out/'libCADGeometry.a'),'@'+str(r/f'.build/drafted-sheet-20261014/{lane}/dependencies.rsp'),'-o',str(exe)],name+'-regression-compile',seconds=180)
  runtime=[str(exe)]if lane!='wasm'else['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'),str(exe),'caller']
  run(runtime,name+'-regression-runtime',seconds=180);products[str(exe)]=sha(exe);products[str(frozen)]=sha(frozen)
 (out/'regression-products.json').write_text(json.dumps(products,indent=2)+'\n')
