from pathlib import Path
import json,hashlib,re,subprocess,time
root=Path.cwd();out=root/'.build/cs-poly-01-current-wasm'; gen=out/'generated';gen.mkdir(exist_ok=True)
rpath=root/'Tests/OriginalPolylineFieldFamilyVerification/Evidence/wasm/receipt.json';r=json.loads(rpath.read_text())
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
checks={str(rpath):digest(rpath)}
for group in ('inputs','product'):
 for n,h in r[group].items():
  if digest(n)!=h:
   assert n in json.loads((out/'replaced-dispatch-premises.json').read_text()),n
  checks[n]=digest(n)
for n,h in r['logs'].items():
 p=rpath.parent/n;assert digest(p)==h;checks[str(p)]=h
call=next(x['command'] for x in r['runs'] if x['label']=='compile-source-domain')
flags=call[:call.index('-emit-library')]
for index,flag in enumerate(flags[:-1]):
 if flag=='-num-threads':flags[index+1]='2'
adapter=Path(next(x for x in call if x.endswith('PolylineLiftAdapters.swiftmodule'))).parent
flags[1:1]=['-I',str(out/'lift-source')]
flags+=['-I',str(adapter)]
imports=['import CADCore','@testable import CADGeometry','@testable import PolylineLiftAdapters']
for x in call:
 if x.endswith('.swift'):
  for kind,name in re.findall(r'^public\s+(?:final\s+)?(struct|class|enum|protocol|typealias)\s+(\w+)',Path(x).read_text(),re.M):
   imports.append(f'import {kind} PolylineLiftAdapters.{name}')
imports += ['import struct PolylineLiftAdapters.OriginalPolynomialSurfaceLiftGraphReduction','import protocol PolylineLiftAdapters.OriginalPolynomialSurfaceLiftGraphReducing','import struct PolylineLiftAdapters.DefaultOriginalPolynomialSurfaceLiftGraphReducer']
header='\n'.join(dict.fromkeys(imports))+'\n'
paths=[]
for component in ['ExactRealRoot','ExactRealCell','ExactRealTopology','ExactParametricRelation','ExactGeometricRelation']:
 paths+=sorted((root/'Sources/CADGeometry/RationalBivariateAlgebra'/component).glob('*.swift'))
paths+=[p for p in sorted((root/'Tests/OriginalGraphRelationVerification/Sources/IssuedGraphs').glob('*.swift')) if p.name not in {'DefaultOriginalOffsetGraphFamilyPreparer.swift','DefaultOriginalRationalGraphFamilyPreparer.swift'}]
paths+=sorted((root/'Tests/OriginalGraphRelationVerification/Sources/IssuedGeometry').glob('*.swift'))
for name in ['OriginalLiftPlaneParameterRestriction','OriginalPlaneGraphCompiling','OriginalIssuedPlaneGraph','DefaultOriginalPlaneGraphCompiler','OriginalLiftPlaneRelations','OriginalLiftPlaneRelationResolving','DefaultOriginalLiftPlaneRelationResolver']:
 paths.append(root/'Sources/CADGeometry/NativeExactRelations'/(name+'.swift'))
for name in ['OriginalIssuedGeometricPublication','OriginalLiftPlaneGeometricRelations']:
 paths.append(root/'Sources/CADGeometry/NativeExactGeometricRelations'/(name+'.swift'))
for name in ['NativeExactGeometricRelations/NativeExactGeometryPublicationFailure.swift','RationalBivariateAlgebra/GeometryExactScalarFailure.swift']:
 paths.append(root/'Sources/CADGeometry'/name)
generated=[]
for p in dict.fromkeys(p.resolve() for p in paths):
 checks[str(p)]=digest(p);q=gen/p.name;q.write_text(header+p.read_text());checks[str(q)]=digest(q);generated.append(str(q))
checks[str(Path(__file__).resolve())]=digest(__file__)
(out/'inputs.json').write_text(json.dumps(checks,indent=2)+'\n')
command=[*flags,'-emit-library','-static','-emit-module','-module-name','PublicLiftPlane',*generated,'-emit-module-path',str(out/'PublicLiftPlane.swiftmodule'),'-o',str(out/'libPublicLiftPlane.a')]
(out/'command.json').write_text(json.dumps(command,indent=2)+'\n')
start=time.monotonic()
with (out/'compile.log').open('w') as log:
 try: code=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240).returncode
 except subprocess.TimeoutExpired:code=124
(out/'compile-run.json').write_text(json.dumps({'command':command,'timeoutSeconds':240,'elapsedSeconds':time.monotonic()-start,'exitCode':code},indent=2)+'\n')
print('compile',code,'seconds',round(time.monotonic()-start,3),'files',len(generated),flush=True)
if code:print((out/'compile.log').read_text()[:18000])
raise SystemExit(code)
