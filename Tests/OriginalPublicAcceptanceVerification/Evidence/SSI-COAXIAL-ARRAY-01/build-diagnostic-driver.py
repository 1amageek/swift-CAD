from pathlib import Path
import ast,hashlib,json,os,signal,subprocess,time
r=Path.cwd();b=r/'.build/coaxial-ssi-array-20261014-v4';out=b/'embedded-imported';out.mkdir(exist_ok=True);lane='embedded';sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
n=next(n for n in ast.parse((r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text()).body if isinstance(n,ast.FunctionDef)and n.name=='run');exec(compile(ast.Module(body=[n],type_ignores=[]),'bounded-run','exec'))
accepted=json.loads((b/'embedded/accepted-premises.json').read_text())
for p,h in accepted['products'].items():assert sha(p)==h,p
for p,h in json.loads((b/'source-premises.json').read_text()).items():assert sha(r/p)==h,p
c=json.loads((b/'embedded-module-mandatory/module.json').read_text())['command'];c=[str(out/'CADGeometry.swiftmodule')if v==str(b/'embedded-module-mandatory/CADGeometry.swiftmodule')else v for v in c];c+=['-emit-library','-static','-o',str(out/'libCADGeometry.a')]
run(c,'CADGeometry',seconds=1200)
(out/'geometry-products.json').write_text(json.dumps({str(out/p):sha(out/p)for p in ['CADGeometry.swiftmodule','libCADGeometry.a']},indent=2)+'\n')
flags=json.loads((b/'embedded-import-diagnostic/minimal-module-only-typecheck.json').read_text())['command'];flags=flags[:flags.index('-typecheck')];flags=[str(out)if v==str(b/'embedded-module-only')else v for v in flags]
wrapper=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
for name,paths,extra in [('public',[str(b/'inputs/Tests/OriginalPublicAcceptanceVerification/CoaxialSSIArrayAcceptance.swift')],[]),('kernel',[str(b/'kernel-native'/p)for p in ['BooleanIntersectionGraph.swift','BooleanFaceSurfaceIntersection.swift','BooleanFacePairCandidate.swift','BooleanBoundaryContact.swift','BooleanBoundaryContactGeometry.swift','CoaxialSSIArrayKernelAcceptance.swift']],[str(r/'.build/trimmed-fold-20261013/edge-embedded/libCADTopology.a')])]:
 exe=out/(name+'.wasm')
 run(flags+['-module-name','CoaxialImported'+name.title(),*paths,str(out/'libCADGeometry.a'),*extra,'@'+str(r/'.build/drafted-sheet-20261014/embedded/dependencies.rsp'),'-o',str(exe)],name+'-compile',seconds=180)
 run(['/usr/local/bin/node',str(wrapper),str(exe),'caller'],name+'-runtime',seconds=180)
(out/'accepted-products.json').write_text(json.dumps({str(out/p):sha(out/p)for p in ['CADGeometry.swiftmodule','libCADGeometry.a','public.wasm','kernel.wasm']},indent=2)+'\n')
(out/'accepted-premises.json').write_text(json.dumps(accepted,indent=2)+'\n')
