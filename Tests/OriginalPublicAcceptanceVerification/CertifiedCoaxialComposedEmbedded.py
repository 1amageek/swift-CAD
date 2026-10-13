from pathlib import Path
import ast,json,hashlib,os,signal,subprocess,time
r=Path.cwd();lane='embedded';out=r/'.build/certified-coaxial-public-20261014-v2/embedded';sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
module=ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text());run_node=next(n for n in module.body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[run_node],type_ignores=[]),'bounded-run','exec'))
inputs=json.loads((out.parent/'source-premises.json').read_text())
for p,h in inputs.items():assert sha(r/p)==h,p
for p,h in json.loads((out/'geometry-products.json').read_text()).items():assert sha(p)==h,p
fixture=r/'Tests/OriginalPublicAcceptanceVerification/CertifiedCoaxialPublicAcceptance.swift'
composed=out/'CertifiedCoaxialPublicAcceptance.swift';composed.write_text(fixture.read_text().replace('import CADGeometry\n',''))
cmd=json.loads((out/'CADGeometry-thread1.json').read_text())['command'];flags=cmd[:cmd.index('-emit-module')]
# Preserve Onone, WMO and the exact production module name. The executable owns
# the original production declarations and invokes the same public API bodies.
exe=out/'Public-composed.wasm'
command=flags+['-module-name','CADGeometry','@'+str(out/'CADGeometry.rsp'),str(composed),'@'+str(r/'.build/drafted-sheet-20261014/embedded/dependencies.rsp'),'-o',str(exe)]
run(command,'public-composed-compile',seconds=420)
wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
run(['/usr/local/bin/node',str(wrapper),str(exe),'caller'],'public-composed-runtime',seconds=180)
(out/'accepted-composed.json').write_text(json.dumps(dict(sourceInputs=inputs,fixtureSHA256=sha(fixture),composedFixtureSHA256=sha(composed),executableSHA256=sha(exe),transformation='Only import CADGeometry is omitted for same-module composition.'),indent=2)+'\n')
