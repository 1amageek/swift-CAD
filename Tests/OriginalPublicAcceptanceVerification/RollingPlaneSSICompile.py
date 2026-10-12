from pathlib import Path
import json,hashlib,subprocess,time,signal,os
r=Path.cwd();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();base=r/'.build/coons-ssi-recovery-20261012/native-public';out=r/'.build/rolling-ssi-20261013/native';out.mkdir(parents=True,exist_ok=True)
changed=[r/'Sources/CADGeometry'/p for p in ['RationalBivariateAlgebra/ExactScalar/OriginalExactScalarDomain.swift','RationalBivariateAlgebra/ExactScalar/ExactRationalCoefficient+SquareRoot.swift','DefaultSurfaceSurfaceIntersector.swift','DefaultSurfaceSurfaceIntersector+Result.swift','OriginalSourceIssuance/OriginalRollingBallGraphReduction.swift','OriginalSourceIssuance/DefaultOriginalRollingBallGraphReducer.swift','NativeExactRelations/DefaultOriginalRollingBallGraphFamilyPreparer.swift','NativeExactRelations/OriginalRollingBallGraphFamilyCoverage.swift','NativeExactGeometricRelations/OriginalRetainedRollingPlanePublicProducer.swift','NativeExactGeometricRelations/OriginalSurfacePlaneSection.swift','NativeExactGeometricRelations/OriginalRollingPlaneGeometricRelations.swift','NativeExactGeometricRelations/DefaultOriginalRollingPlaneSectionResolver.swift','NativeExactGeometricRelations/OriginalIssuedGeometricRelationReading.swift','NativeExactGeometricRelations/OriginalLiftPlaneGeometricRelations.swift','NativeExactGeometricRelations/OriginalIssuedGeometricRelations.swift','NativeExactGeometricRelations/OriginalSurfacePlaneGeometricRelations.swift','NativeExactGeometricRelations/OriginalRevolutionAxisGeometricRelations.swift']]
meta=json.loads((base/'objects.json').read_text());sources=sorted((r/'Sources/CADGeometry').rglob('*.swift'));inputs={str(p):sha(p)for p in sources}
for p,h in meta['inputs'].items():
 if Path(p)not in changed:
  if p.endswith('/RationalBivariateAlgebra/ExactRationalCoefficient+SquareRoot.swift'):
   assert sha(r/'Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/ExactRationalCoefficient+SquareRoot.swift')==h,p
  else:assert sha(Path(p))==h,p
products=json.loads((base/'linked-products.json').read_text())
for p,h in products.items():
 if p.endswith('/CoonsPlaneSSIAcceptance.swift'):continue
 assert sha(Path(p))==h,p
if os.environ.get('ROLLING_REUSE')=='1':
 for name in ['module','objects']:
  proof=json.loads((out/(name+'.json')).read_text());assert proof['exitCode']==0 and proof['inputs']==inputs
cmd=json.loads((base/'module.json').read_text())['command'];flags=cmd[1:cmd.index('-whole-module-optimization')];flags[-1]=str(out/'module-cache')
rsp=out/'sources.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in sources)+'\n')
def run(cmd,name):
 start=time.monotonic()
 with (out/(name+'.log')).open('w')as log:
  p=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  try:code=p.wait(timeout=120)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
 (out/(name+'.json')).write_text(json.dumps(dict(command=cmd,inputs=inputs,exitCode=code,elapsedSeconds=time.monotonic()-start,logSHA256=sha(out/(name+'.log'))),indent=2));print(name,code,time.monotonic()-start,flush=True)
 if code:print((out/(name+'.log')).read_text()[-12000:]);raise SystemExit(code)
if os.environ.get('ROLLING_REUSE')!='1':run([cmd[0],*flags,'-whole-module-optimization','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'@'+str(rsp)],'module')
others=out/'others.rsp';others.write_text('\n'.join(json.dumps(str(p))for p in sources if p not in changed)+'\n');prim=[];outputs=[]
for p in changed:prim+=['-primary-file',str(p)];outputs+=['-o',str(out/(p.stem+'.o'))]
if os.environ.get('ROLLING_REUSE')!='1':run([cmd[0],'-frontend','-c',*flags,*prim,'@'+str(others),*outputs],'objects')
oldrsp=base/'link-objects.rsp';objects=[]
for line in oldrsp.read_text().splitlines():
 p=Path(json.loads(line));local=out/p.name;objects.append(local if local.exists() and p.stem in {q.stem for q in changed}else p)
for p in changed:
 obj=out/(p.stem+'.o')
 if obj not in objects:objects.append(obj)
(out/'link-objects.rsp').write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n');(out/'linked-products.json').write_text(json.dumps({str(p):sha(p)for p in objects+[out/'CADGeometry.swiftmodule']},indent=2))
fixture=r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIStop.swift'
run([cmd[0],'-parse-as-library','-package-name','NativeExactRelationVerification','-swift-version','6','-I',str(out),'-I',flags[flags.index('-I')+1],'-sdk',flags[flags.index('-sdk')+1],'-target','arm64-apple-macosx15.0',str(fixture),'@'+str(out/'link-objects.rsp'),'-o',str(out/'Stop')],'fixture')
run([str(out/'Stop')],'runtime')
print((out/'runtime.log').read_text(),flush=True)
