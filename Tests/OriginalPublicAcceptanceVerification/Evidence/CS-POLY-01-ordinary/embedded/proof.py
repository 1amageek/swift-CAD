from pathlib import Path
import json,subprocess,time,hashlib,sys
root=Path.cwd();out=root/'.build/cs-poly-01-current-embedded';r=json.loads((root/'Tests/OriginalPolylineFieldFamilyVerification/Evidence/embedded/receipt.json').read_text())
call=next(x['command'] for x in r['runs'] if x['label']=='compile-link')
flags=call[:call.index('-I',call.index('-emit-executable')+1)] if False else next(x['command'] for x in r['runs'] if x['label']=='compile-source-domain')
flags=flags[:flags.index('-emit-library')]
adapter=Path(next(x for x in call if x.endswith('libPolylineLiftAdapters.a')))
flags[1:1]=['-I',str(out/'lift-source')]
flags+=['-I',str(out),'-I',str(adapter.parent)]
files=[]
for path in [root/'Tests/OriginalPolylineSurfaceLiftVerification/Proof.swift',root/'Tests/OriginalPolylineAtlasLiftVerification/Proof.swift']:
 q=out/('Fixture'+str(len(files))+'.swift');q.write_text(path.read_text().replace('@main struct','struct'));files.append(q)
proof=out/'Proof.swift'
if len(sys.argv)>1 and sys.argv[1]=='prepared-port':
 proof=out/'PreparedPortProof.swift'
 proof.write_text((root/'Tests/OriginalPublicAcceptanceVerification/PreparedRetainedLiftPlanePortProbe.swift').read_text())
s=proof.read_text();s=s
proof.write_text(s)
archives=[str(out/'lift-source/libPolylineLiftAdapters.a') if Path(x).name == 'libPolylineLiftAdapters.a' else x for x in call if x.endswith('.a')]
cmd=[*flags,'-parse-as-library','-emit-executable','-module-name','RetainedLiftPlaneProof',str(proof),*map(str,files),str(out/'libPublicLiftPlanePort.a'),str(out/'libPublicLiftPlane.a'),*archives,'-o',str(out/'proof')]
mode_flag={'gp':'PUBLIC_PROOF_GP','selections':'PUBLIC_PROOF_SELECTIONS','resources':'PUBLIC_PROOF_RESOURCES','cancel-final':'PUBLIC_PROOF_CANCEL_FINAL','cancel-entry':'PUBLIC_PROOF_CANCEL_ENTRY'}.get(sys.argv[1] if len(sys.argv)>1 else 'ordinary')
if mode_flag:cmd[1:1]=['-D'+mode_flag]
import re
base_command=json.loads((out/'command.json').read_text())
imports=['import CADCore','@testable import CADGeometry','@testable import PolylineLiftAdapters','@testable import PublicLiftPlane','@testable import PublicLiftPlanePort','import struct PolylineLiftAdapters.OriginalFiniteBSplineCharts','import struct PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer','import struct PublicLiftPlanePort.DefaultCurveSurfaceIntersector','import struct PublicLiftPlanePort.CurveSurfaceIntersectionResult']
adapter_command=json.loads((out/'adapter-command.json').read_text())
for path in [Path(x) for x in adapter_command if x.endswith('.swift')]:
 for kind,name in re.findall(r'^public\s+(?:final\s+)?(struct|class|enum|protocol|typealias)\s+(\w+)',path.read_text(),re.M):
  imports.append(f'import {kind} PolylineLiftAdapters.{name}')
for path in [Path(x) for x in base_command if x.endswith('.swift')]:
 for kind,name in re.findall(r'^public\s+(?:final\s+)?(struct|class|enum|protocol|typealias)\s+(\w+)',path.read_text(),re.M):
  imports.append(f'import {kind} PublicLiftPlane.{name}')
header='\n'.join(dict.fromkeys(imports))+'\n'
if len(sys.argv)>1 and sys.argv[1]=='prepared-port':proof.write_text(header+proof.read_text())
extra_sources=[]
for source in ['Sources/CADGeometry/OriginalSourceIssuance/OriginalParametricGraphIssuing.swift','Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalRationalGraphIssuer.swift','Tests/OriginalGraphRelationVerification/Sources/IssuedGraphs/DefaultOriginalRationalGraphFamilyPreparer.swift','Sources/CADGeometry/NativeExactGeometricRelations/OriginalIssuedGraphResultResolving.swift','Sources/CADGeometry/NativeExactGeometricRelations/DefaultCurveSurfaceIntersector+IssuedGraphs.swift','Tests/OriginalPublicAcceptanceVerification/PreparedGraphPublicationRegression.swift']:
 p=root/source;q=out/('Regression-'+p.name);q.write_text(header+p.read_text());extra_sources.append(str(q))
cmd[-2:-2]=extra_sources
link_tail=[]
for token in call[call.index(next(x for x in call if x.endswith('.swift'))):call.index('-o')]:
 if not token.endswith('.swift') and not token.endswith('.a'):link_tail.append(token)
cmd[-2:-2]=link_tail+['-Xlinker','-lc++abi']
(out/'proof-command.json').write_text(json.dumps(cmd,indent=2)+'\n')
with (out/'proof-link.log').open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('link',r.returncode,flush=True)
if r.returncode:print((out/'proof-link.log').read_text()[:18000]);raise SystemExit(r.returncode)
(out/'linked-product.json').write_text(json.dumps({str(out/'proof'):hashlib.sha256((out/'proof').read_bytes()).hexdigest()},indent=2)+'\n')
start=time.monotonic()
mode=sys.argv[1] if len(sys.argv)>1 else 'public'
runtime=['/usr/local/bin/node',str(root/'Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs'),str(out/'proof'),*sys.argv[1:]]
with (out/('proof-'+mode+'-runtime.log')).open('w') as log:r=subprocess.run(runtime,stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('runtime',r.returncode,round(time.monotonic()-start,3),flush=True);print((out/('proof-'+mode+'-runtime.log')).read_text()[:18000])
(out/('proof-'+mode+'-run.json')).write_text(json.dumps({'compile':cmd,'runtime':runtime,'timeoutSeconds':120,'exitCode':r.returncode,'elapsedSeconds':time.monotonic()-start},indent=2)+'\n')
raise SystemExit(r.returncode)
