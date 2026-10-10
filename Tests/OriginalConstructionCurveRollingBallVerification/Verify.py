#!/usr/bin/env python3
"""Verify actual retained construction-curve rolling-ball consumers without broad CAD rebuilding."""
import argparse,hashlib,json,subprocess,time,uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);p.add_argument('--output',type=Path);args=p.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=args.output.resolve() if args.output else base/'Evidence'/args.lane;out.mkdir(parents=True,exist_ok=False)
prior=root/'Tests/OriginalDerivativeLiftHostVerification/Evidence'/args.lane/'receipt.json';r=json.loads(prior.read_text());assert r['success']
checks={}
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def add(p,h=None):
 p=Path(p).resolve();h=h or digest(p);assert digest(p)==h,str(p);checks[str(p)]=h;return p
add(prior);add(__file__)
for group in ['inputs','product']:
 for n,h in r[group].items():
  if Path(n).name=='OriginalSplineTraversalPolynomialPiece.swift':
   current=Path(n).read_text();lo=current.index('    /// Reads an existing normalized construction');hi=current.index('    /// Reuses a retained normalized guide',lo)
   assert hashlib.sha256((current[:lo]+current[hi:]).encode()).hexdigest()==h,'Original numerical payload changed beyond additive entry'
   add(n)
  else:add(n,h)
for n,h in r['logs'].items():add(prior.parent/n,h)
scratch=root/'.build/m4-construction-curve-rolling-ball'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
original=add(root/'Tests/OriginalDerivativeLiftHostVerification/Proof.swift')
command=next(x['command'] for x in r['runs'] if x['label']=='compile-link').copy()
command[command.index(str(original))]=str(add(base/'Proof.swift'))
adapter_command=next(x['command'] for x in r['runs'] if x['label'].endswith('compile-adapters'))
flags=adapter_command[:max(i for i,x in enumerate(adapter_command) if x=='-enable-testing')]
names=['OriginalRollingBallCurveSnapshot','OriginalRollingBallCurveSnapshotProvider','OriginalRollingBallCurveGraphEvidence','OriginalRollingBallCurveGraphCoverage','DefaultOriginalRollingBallCurveGraphPreparer','BSplineCurve3D+OriginalSourceReading','OriginalBSplineCurveSnapshotProvider','OriginalNativeCurveFamilySnapshotProvider','OriginalGraphRollingBallSnapshot','OriginalGraphRollingBallSnapshotProvider','OriginalPlaneDerivativeCurveSnapshot','OriginalPlaneDerivativeCurveSnapshotProvider','OriginalRetainedGuideCurveSnapshot','OriginalRetainedGuideCurveSnapshotProvider','OriginalRetainedConstructionCurveSnapshot','OriginalRetainedConstructionCurveSnapshotProvider']
header='import CADCore\n@testable import func CADGeometry.exactScalarPayloadBytes\n@testable import RetainedHostAdapters\nimport enum CADGeometry.Curve3D\nimport struct CADGeometry.BSplineCurve3D\nimport struct CADGeometry.BSplineSurface3D\nimport struct CADGeometry.BSplineCurve2D\nimport struct CADGeometry.OriginalExactScalarDomain\nimport protocol CADGeometry.ExactScalarAdmission\nimport enum CADGeometry.ExactScalarFailure\n'
files=[]
for name in names:
 source=add(root/'Sources/CADGeometry/OriginalSourceIssuance'/(name+'.swift'))
 generated=scratch/(name+'.swift');generated.write_text(header+('@testable import struct ConstructionPayloadAccess.OriginalSplineTraversalPolynomialPiece\n' if name.startswith('OriginalRetainedConstructionCurveSnapshot') else '')+('\n@testable import struct CADGeometry.OriginalPlaneDerivativeCurve3D\n@testable import struct CADGeometry.OriginalGuideTraversalChain3D\n@testable import struct CADGeometry.OriginalGuideEndpointConnectorCurve3D\n@testable import enum CADGeometry.ExactScalarNumericAccess\nimport struct CADGeometry.ExactPolynomialDomain\nimport struct CADGeometry.ExactPolynomial\nimport struct CADGeometry.ExactPolynomialTerm\nimport struct CADGeometry.OriginalExactScalar\nimport struct CADGeometry.ExactScalarDepth\n' if name.startswith(('OriginalPlaneDerivativeCurveSnapshot','OriginalRetainedGuideCurveSnapshot','OriginalRetainedConstructionCurveSnapshot')) else '')+('@testable import struct CADGeometry.OriginalSplineTraversalPolynomialPiece\n' if name.startswith(('OriginalPlaneDerivativeCurveSnapshot','OriginalRetainedGuideCurveSnapshot')) else '')+source.read_text());files.append(add(generated))
for relative in ['RollingBall/RollingBallBlendSurface3D.swift','RollingBall/RollingBallBlendSurface3D+Enclosure.swift','DefaultSurfaceRegularityValidator.swift','StrictDecoding.swift']:
 source=add(root/'Sources/CADGeometry'/relative)
 generated=scratch/source.name;generated.write_text('import CADCore\n@testable import CADGeometry\n@testable import RetainedHostAdapters\n'+source.read_text());files.append(add(generated))
producer=add(root/'Sources/CADGeometry/OriginalCoons/OriginalSplineTraversalPolynomialPiece.swift')
text=producer.read_text();start=text.index('    /// Reads an existing normalized construction');end=text.index('    /// Reuses a retained normalized guide',start);methods=text[start:end]
helpers=scratch/'ConstructionPayloadHelpers.swift';helpers.write_text('import CADCore\n@testable import CADGeometry\n'+text);add(helpers)
helper_archive=scratch/'libConstructionPayloadAccess.a'
helper_command=[*flags,'-enable-testing','-emit-library','-static','-emit-module','-module-name','ConstructionPayloadAccess',str(helpers),'-emit-module-path',str(scratch/'ConstructionPayloadAccess.swiftmodule'),'-o',str(helper_archive)]
archive=scratch/'libCallerAdapters.a'
compile_command=[*flags,'-I',str(scratch),'-enable-testing','-emit-library','-static','-emit-module','-module-name','CallerAdapters',*map(str,files),'-emit-module-path',str(scratch/'CallerAdapters.swiftmodule'),'-o',str(archive)]
command[command.index('-parse-as-library'):command.index('-parse-as-library')]=['-I',str(scratch)]
command.insert(command.index('-o'),str(archive));command.insert(command.index('-o'),str(helper_archive))
artifact=scratch/('ConstructionCurveRollingBallProof.wasm' if args.lane in ['wasm','embedded'] else 'ConstructionCurveRollingBallProof');command[command.index('-o')+1]=str(artifact)
runs=[]
def run(label,cmd):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:result=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 runs.append(dict(label=label,command=cmd,elapsedSeconds=time.monotonic()-start,exitCode=result.returncode,timeoutSeconds=120))
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(label,result.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 if result.returncode:raise SystemExit(result.returncode)
 if label=='proof':
  output=(out/(label+'.log')).read_text();assert 'FAIL' not in output
  for marker in ['PASS retained rolling-ball child capabilities','PASS retained rolling-ball actual product and DI','PASS retained rolling-ball resource/cancel/lifetime','PASS existing rolling-ball curve caller','PASS retained construction child laws','PASS retained construction source authority','PASS retained construction rolling-ball and mixed product','PASS retained construction resources/cancel/lifetime']:
   assert marker in output,marker
old=add(root/'Tests/OriginalRetainedNativePcurveLiftVerification/CallerProof.swift')
regression=scratch/'NativeCallerRegression.swift';regression.write_text(old.read_text().replace('@main struct RetainedLiftCallerProof','struct RetainedLiftCallerProof'));add(regression)
command.insert(command.index('-o'),str(regression))
previous=add(root/'Tests/OriginalRetainedRollingBallVerification/Proof.swift')
retained_regression=scratch/'RetainedRollingBallRegression.swift'
retained_regression.write_text(previous.read_text().replace('@main struct RetainedRollingBallProof','struct RetainedRollingBallProof'));add(retained_regression)
command.insert(command.index('-o'),str(retained_regression))
derivative=add(root/'Tests/OriginalDerivativeRollingBallVerification/Proof.swift')
derivative_regression=scratch/'DerivativeLiftRollingBallRegression.swift'
derivative_regression.write_text(derivative.read_text().replace('@main struct DerivativeRollingBallProof','struct DerivativeRollingBallProof'));add(derivative_regression)
command.insert(command.index('-o'),str(derivative_regression))
direct=add(root/'Tests/OriginalDerivativeCurveRollingBallVerification/Proof.swift')
direct_regression=scratch/'DirectDerivativeRollingBallRegression.swift'
direct_regression.write_text(direct.read_text().replace('@main struct DerivativeCurveRollingBallProof','struct DerivativeCurveRollingBallProof'));add(direct_regression)
command.insert(command.index('-o'),str(direct_regression))
guide=add(root/'Tests/OriginalGuideCurveRollingBallVerification/Proof.swift')
guide_regression=scratch/'GuideRollingBallRegression.swift';guide_regression.write_text(guide.read_text().replace('@main struct GuideCurveRollingBallProof','struct GuideCurveRollingBallProof'));add(guide_regression)
command.insert(command.index('-o'),str(guide_regression))
(out/'inputs-before-compile.json').write_text(json.dumps(checks,indent=2)+'\n')
run('compile-payload-helper',helper_command);add(helper_archive);add(scratch/'ConstructionPayloadAccess.swiftmodule')
run('compile-caller',compile_command);add(archive);add(scratch/'CallerAdapters.swiftmodule')
run('compile-link',command);add(artifact)
runtime=next(x['command'] for x in r['runs'] if x['label']=='proof').copy();runtime[-1]=str(artifact)
run('proof',runtime)
for path in out.glob('*.log'):
 assert not any(x in path.read_text() for x in ['warning:','error:','actor-isolated function','data race detected','null function','function signature mismatch']),str(path)
for n,h in checks.items():assert digest(n)==h,n
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,product={str(artifact):digest(artifact)},numericalPayload=dict(sourceSHA256=hashlib.sha256((text[:start]+text[end:]).encode()).hexdigest(),currentSHA256=digest(producer),additiveMethodSHA256=hashlib.sha256(methods.encode()).hexdigest(),difference='The exact changed original producer file is freshly compiled with ordinary access control. Its prior storage and all old algorithms match the inherited receipt after stripping one additive entry. No broad numerical/lower rebuild.'),runs=runs,logs={x.name:digest(x) for x in out.glob('*.log')}),indent=2)+'\n')
