from pathlib import Path
import hashlib,json,subprocess,time,os,signal,sys,shutil
root=Path.cwd();lane=sys.argv[1];base='65f45e9a'
e=root/'Tests/OriginalPublicAcceptanceVerification/Evidence'
parent=e/'CS-POLY-NORMAL-SUBNORMAL-01'/lane
out=root/('.build/cs-poly-coinc-'+lane+'-20261011'+os.environ.get('COINC_ATTEMPT',''));out.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def write(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
summary=read(parent.parent/'receipt.json');assert sha(parent/'receipt.json')==summary['lanes'][lane]['receiptSHA256']
r=read(parent/'receipt.json');assert r['success']
for p,h in r['files'].items():assert sha(parent/p)==h,p
for p,h in read(parent/'products.json').items():assert sha(p)==h,p
ordinary=e/'CS-POLY-01-ordinary'/lane
original=read(ordinary/'receipt.json');assert sha(ordinary/'receipt.json')==r['parentSHA256']
for p,h in original['files'].items():assert sha(ordinary/p)==h,p
pr=read(original['parentReceipt']);assert sha(original['parentReceipt'])==original['parentSHA256']
inputs=dict(pr['inputs']);inputs.update(read(ordinary/'inputs.json'))
snapshots=read(ordinary/'compiler-source-snapshot.json')
for p,h in inputs.items():
 if p in [str(root/'Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift'),str(root/'Sources/CADGeometry/CurveSurfaceOverlap/CurveSurfaceIntersectionResult.swift')]:
  assert hashlib.sha256(subprocess.check_output(['git','show',base+':'+str(Path(p).relative_to(root))])).hexdigest()==h,p
  continue
 q=Path(snapshots[p]['path']) if p in snapshots else Path(p)
 if p in read(parent/'changed-premises.json'):
  continue
 assert sha(q)==h,p
for p,h in read(ordinary/'products.json').items():assert sha(p)==h,p
for p,h in pr['product'].items():assert sha(p)==h,p
for p,h in pr['logs'].items():assert sha(Path(original['parentReceipt']).parent/p)==h,p
for v in snapshots.values():assert sha(v['path'])==v['sha256']
write(out/'parent-admission.json',dict(parentReceipt=str(parent/'receipt.json'),parentSHA256=sha(parent/'receipt.json'),lowerInputs=len(inputs)))
command=read(parent/'port-command.json')
newpaths=[str(p) for p in sorted((root/'Sources/CADGeometry/NativeExactGeometricRelations').glob('*ContainedLiftPlane*.swift'))]
newpaths += [str(root/'Sources/CADGeometry/RationalBivariateAlgebra/ExactGeometricRelation'/p) for p in ['ExactPolynomialCurveMapEvidence.swift','ExactPolynomialCurveMapCertifying.swift','DefaultExactPolynomialCurveMapCertifier.swift']]
producer='Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift'
oldbody=subprocess.check_output(['git','show',base+':'+producer],text=True)
producerarg=next(p for p in command if p.endswith('OriginalRetainedLiftPlanePublicProducer.swift'))
prefix=Path(producerarg).read_text().split(oldbody)[0];assert oldbody in Path(producerarg).read_text()
production={};compiled={};deltas={}
for i,arg in enumerate(command):
 if not arg.endswith('.swift'):continue
 text=Path(arg).read_text();relative=None
 for p in root.joinpath('Sources/CADGeometry').rglob(Path(arg).name.split('-',1)[-1]):
  if p.name not in ['OriginalRetainedLiftPlanePublicProducer.swift','CurveSurfaceIntersectionResult.swift','OriginalLiftPlanePointPublisher.swift']:continue
  relative=str(p.relative_to(root));break
 if relative:
  previous=subprocess.check_output(['git','show',base+':'+relative],text=True)
  assert text.count(previous)==1,(relative,arg)
  changed=(root/relative).read_text();text=text.replace(previous,changed)
  target=out/Path(relative).name;target.write_text(text);command[i]=str(target)
  production[relative]=sha(root/relative);deltas[relative]={'previous':hashlib.sha256(previous.encode()).hexdigest(),'current':production[relative]}
 compiled[command[i]]=sha(command[i])
for p in newpaths:
 target=out/Path(p).name;target.write_text(prefix+Path(p).read_text());command.append(str(target));compiled[str(target)]=sha(target);production[str(Path(p).relative_to(root))]=sha(p)
command[command.index('-o')+1]=str(out/'libPublicLiftPlanePort.a');command[command.index('-emit-module-path')+1]=str(out/'PublicLiftPlanePort.swiftmodule')
proof=read(parent/'proof-command.json')
oldout=root/('.build/cs-poly-subnormal-'+lane+'-20261011')
proof=[str(out) if x==str(oldout) else str(out/'libPublicLiftPlanePort.a') if x==str(oldout/'libPublicLiftPlanePort.a') else x for x in proof]
for i,x in enumerate(proof):
 if x.endswith('/Proof.swift') and 'enum Mode' in Path(x).read_text():
  target=out/'Proof.swift';target.write_text((root/'Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift').read_text());proof[i]=str(target)
proof[proof.index('-o')+1]=str(out/'proof')
if lane=='embedded':proof[1:1]=['-DPUBLIC_PROOF_CONTAINED_ALL']
write(out/'production.json',production);write(out/'changed-premises.json',deltas);write(out/'compiler-inputs.json',compiled);write(out/'port-command.json',command);write(out/'proof-command.json',proof)
runs=[]
def run(c,label,timeout):
 start=time.monotonic();log=out/(label+'.log')
 with log.open('w') as f:
  p=subprocess.Popen(c,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
  try:code=p.wait(timeout=timeout)
  except subprocess.TimeoutExpired:
   os.killpg(p.pid,signal.SIGTERM);p.wait();raise
 result=dict(label=label,command=c,timeoutSeconds=timeout,exitCode=code,elapsedSeconds=time.monotonic()-start,logSHA256=sha(log));runs.append(result);write(out/'runs.json',runs)
 print(lane,label,code,round(result['elapsedSeconds'],3),flush=True)
 if code:print(log.read_text()[:18000],flush=True);raise SystemExit(code)
 if label.startswith('runtime'):print(log.read_text()[:2500],flush=True)
if os.environ.get('COINC_REUSE_PORT'):
 previous=Path(os.environ['COINC_REUSE_PORT']);assert read(previous/'production.json')==production
 assert {Path(k).name:v for k,v in read(previous/'compiler-inputs.json').items()}=={Path(k).name:v for k,v in compiled.items()}
 assert [x.replace(str(previous),str(out)) for x in read(previous/'port-command.json')]==command
 previousReceipt=previous/('products.json' if (previous/'products.json').exists() else 'port-products.json')
 oldproducts=read(previousReceipt)
 for name in ['libPublicLiftPlanePort.a','PublicLiftPlanePort.swiftmodule']:
  source=previous/name;assert sha(source)==oldproducts[str(source)];shutil.copy2(source,out/name)
 write(out/'reused-port.json',dict(receipt=str(previousReceipt),receiptSHA256=sha(previousReceipt)))
else:
 run(command,'compile-port',300 if lane=='embedded' else 120)
write(out/'port-products.json',{str(p):sha(p) for p in [out/'libPublicLiftPlanePort.a',out/'PublicLiftPlanePort.swiftmodule']})
run(proof,'compile-proof',300 if lane=='embedded' else 120)
product=out/'proof';write(out/'products.json',{str(p):sha(p) for p in [product,out/'libPublicLiftPlanePort.a',out/'PublicLiftPlanePort.swiftmodule']})
if lane in ['wasm','embedded']:
 oldruntime=read(ordinary/'runs.json')[0]['runtime'];runtime=[oldruntime[0],str(root/'Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs'),str(product)]
else:runtime=[str(product)]
for mode in (['contained-all'] if lane=='embedded' else ['positive','contained-resources','contained-cancel-entry','contained-cancel-final','unit-regression','ordinary']):
 run([*runtime,mode],'runtime-'+mode,120)
write(out/'receipt.json',dict(success=True,lane=lane,production=production,parentReceipt=str(parent/'receipt.json'),parentSHA256=sha(parent/'receipt.json'),products=read(out/'products.json'),runs=runs))
