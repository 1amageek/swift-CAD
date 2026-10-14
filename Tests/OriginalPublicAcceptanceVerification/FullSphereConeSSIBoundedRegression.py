from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time,sys
r=Path.cwd();lane=sys.argv[1];base=r/'.build/full-sphere-cone-ssi-20261014/v2';out=base/('bounded-regression-operations-'+lane);out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
m=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());n=next(n for n in m.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'runner','exec'))
for p,h in json.loads((base/lane/'geometry-products.json').read_text()).items():assert sha(p)==h,p
for p,h in json.loads((base/'source-premises.json').read_text()).items():assert sha(r/p)==h,p
c=json.loads((base/lane/'public-compile.json').read_text())['command'];fixture=r/'Tests/OriginalPublicAcceptanceVerification/BoundedSphereConeSSIAcceptance.swift';copy=out/fixture.name;copy.write_bytes(fixture.read_bytes());c[c.index('-module-name')+1]='BoundedSphereConeSSIAcceptance';c[c.index('-module-name')+2]=str(copy);exe=out/('Public.wasm'if lane=='wasm'else'Public');c[-1]=str(exe)
run(c,'compile',seconds=180)
wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
groups=sys.argv[2:] or ['publication-case-'+str(case)+'-'+str(check) for case in range(4) for check in range(7)]+['prepared','terminal']
for group in groups:
 run(['/usr/local/bin/node',str(wrapper),str(exe),group]if lane=='wasm'else[str(exe),group],'runtime-'+group,seconds=180)
(out/'receipt.json').write_text(json.dumps(dict(fixtureSHA256=sha(copy),executableSHA256=sha(exe),geometryProducts=json.loads((base/lane/'geometry-products.json').read_text())),indent=2)+'\n')
