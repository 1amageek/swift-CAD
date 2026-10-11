from pathlib import Path
import json,subprocess,hashlib,time
root=Path.cwd();out=root/'.build/cs-poly-01-current-wasm';target=out/'lift-source';target.mkdir(exist_ok=True)
r=json.loads((root/'Tests/OriginalPolylineFieldFamilyVerification/Evidence/wasm/receipt.json').read_text())
call=next(x['command'] for x in r['runs'] if x['label']=='compile-source-domain'); flags=call[:call.index('-emit-library')]
for index,flag in enumerate(flags[:-1]):
 if flag=='-num-threads':flags[index+1]='2'
files=[x for x in call if x.endswith('.swift')]
checks={}
for name in ['OriginalPolynomialSurfaceLiftGraphReduction','OriginalPolynomialSurfaceLiftGraphReducing','DefaultOriginalPolynomialSurfaceLiftGraphReducer']:
 p=root/'Sources/CADGeometry/OriginalSourceIssuance'/(name+'.swift');q=target/p.name;q.write_text('import CADCore\n@testable import CADGeometry\n'+p.read_text());files.append(str(q))
 for x in [p,q]:checks[str(x)]=hashlib.sha256(x.read_bytes()).hexdigest()
cmd=[*flags,'-emit-library','-static','-emit-module','-module-name','PolylineLiftAdapters',*files,'-emit-module-path',str(target/'PolylineLiftAdapters.swiftmodule'),'-o',str(target/'libPolylineLiftAdapters.a')]
(out/'adapter-command.json').write_text(json.dumps(cmd,indent=2)+'\n');(out/'adapter-inputs.json').write_text(json.dumps(checks,indent=2)+'\n')
start=time.monotonic()
with (out/'adapter-compile.log').open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('adapter compile',r.returncode,round(time.monotonic()-start,3),flush=True)
if r.returncode:print((out/'adapter-compile.log').read_text()[:16000])
raise SystemExit(r.returncode)
