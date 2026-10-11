from pathlib import Path
import json,subprocess,time,hashlib
root=Path.cwd();out=root/'.build/cs-poly-01-current-embedded';base=json.loads((out/'command.json').read_text());flags=base[:base.index('-emit-library')]+['-I',str(out)]
inputs=json.loads((out/'inputs.json').read_text());paths=[]
import re
imports=['import enum PublicLiftPlane.NativeExactGeometryPublicationFailure','import enum PublicLiftPlane.GeometryExactScalarFailure']
for p in [Path(x) for x in base if str(x).endswith('.swift')]:
 if p.name in {'CurveSurfaceIntersectionResult.swift','OriginalRetainedLiftPlaneIntersecting.swift','DefaultCurveSurfaceIntersector+RetainedLiftPlane.swift'}:continue
 for kind,name in re.findall(r'^public\s+(?:final\s+)?(struct|class|enum|protocol|typealias)\s+(\w+)',p.read_text(),re.M):
  imports.append(f'import {kind} PublicLiftPlane.{name}')
extra='\n'.join(dict.fromkeys(imports))+'\n'
for name in ['NativeExactGeometricRelations/ExactIntersectionResultRepresentation.swift','NativeExactGeometricRelations/OriginalIssuedNumericalCurveSurfacePoints.swift','NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift','NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift','NativeExactGeometricRelations/NativeExactPublicAdmission.swift','NativeExactGeometricRelations/NativeExactPublicLimits.swift','DefaultCurveSurfaceIntersector.swift','CurveSurfaceOverlap/DefaultCurveSurfaceIntersector+Overlap.swift','CurveSurfaceOverlap/CurveSurfaceIntersectionResolving.swift','CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift','NativeExactGeometricRelations/OriginalRetainedLiftPlaneIntersecting.swift','NativeExactGeometricRelations/DefaultCurveSurfaceIntersector+RetainedLiftPlane.swift']:
 p=root/'Sources/CADGeometry'/name;q=out/'generated'/p.name;q.write_text('import CADCore\n@testable import CADGeometry\n@testable import PolylineLiftAdapters\n@testable import PublicLiftPlane\n'+extra+p.read_text());paths.append(q)
 for f in [p,q]:inputs[str(f)]=hashlib.sha256(f.read_bytes()).hexdigest()
paths.append(out/'UnselectedOverlapTripwire.swift')
inputs[str(paths[-1])]=hashlib.sha256(paths[-1].read_bytes()).hexdigest()
(out/'port-inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
cmd=[*flags,'-emit-library','-static','-emit-module','-module-name','PublicLiftPlanePort',*map(str,paths),'-emit-module-path',str(out/'PublicLiftPlanePort.swiftmodule'),'-o',str(out/'libPublicLiftPlanePort.a')]
(out/'port-command.json').write_text(json.dumps(cmd,indent=2)+'\n');start=time.monotonic()
with (out/'port-compile.log').open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('port compile',r.returncode,round(time.monotonic()-start,3));print((out/'port-compile.log').read_text()[:18000])
raise SystemExit(r.returncode)
