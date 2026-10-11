from pathlib import Path
import hashlib,json,subprocess,time,os,signal,sys
root=Path.cwd();lane=sys.argv[1];e=root/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-01-ordinary'/lane
out=root/('.build/cs-poly-subnormal-'+lane+'-20261011');out.mkdir(exist_ok=True);assert not (out/'port-command.json').exists()
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def write(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
r=read(e/'receipt.json');check=read(e.parent/'receipt.json');assert sha(e/'receipt.json')==check['lanes'][lane]['receiptSHA256'];assert r['success']
for p,h in r['files'].items():assert sha(e/p)==h,p
parent=Path(r['parentReceipt']);assert sha(parent)==r['parentSHA256'];pr=read(parent)
sources=read(e/'compiler-source-snapshot.json');products=read(e/'products.json');inputs=dict(pr['inputs']);inputs.update(read(e/'inputs.json'))
changedPaths=['Sources/CADGeometry/NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift','Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift']
overrides={}
for relative in changedPaths:
 path=str(root/relative)
 if path in inputs:
  old=subprocess.check_output(['git','show','2c708522:'+relative]);assert hashlib.sha256(old).hexdigest()==inputs[path]
  overrides[path]=dict(previous=inputs[path],current=sha(path));inputs[path]=sha(path)
write(out/'changed-premises.json',overrides)
for p,h in inputs.items():
 q=Path(sources[p]['path']) if p in sources else Path(p)
 assert sha(q)==h,p
for p,h in products.items():assert sha(p)==h,p
for p,h in pr['product'].items():assert sha(p)==h,p
for p,h in pr['logs'].items():assert sha(parent.parent/p)==h,p
for a in sources.values():assert sha(a['path'])==a['sha256']
write(out/'parent-admission.json',dict(parentReceipt=str(e/'receipt.json'),parentSHA256=sha(e/'receipt.json'),effectiveInputs=len(inputs),products=products))
old=root/('.build/cs-poly-01-current-'+lane);libraries=root/('.build/cs-poly-01-ordinary-accepted-20261011/'+lane+'/libraries')
def argument(x):
 p=Path(x)
 if x in sources:return sources[x]['path']
 if x==str(old) or x==str(old/'lift-source'):return str(libraries)
 if p.parent in [old,old/'lift-source'] and x.endswith('.a'):return str(libraries/p.name)
 return x
command=[argument(x) for x in read(e/'port-command.json')]
relative='Sources/CADGeometry/NativeExactGeometricRelations/OriginalLiftPlanePointPublisher.swift'
original=subprocess.check_output(['git','show','2c708522:'+relative],text=True);changed=(root/relative).read_text()
for i,x in enumerate(command):
 if x.endswith('OriginalLiftPlanePointPublisher.swift'):
  s=Path(x).read_text();assert s.count(original)==1
  p=out/'OriginalLiftPlanePointPublisher.swift';p.write_text(s.replace(original,changed));command[i]=str(p)
command[command.index('-o')+1]=str(out/'libPublicLiftPlanePort.a');command[command.index('-emit-module-path')+1]=str(out/'PublicLiftPlanePort.swiftmodule')
if '-num-threads' in command:command[command.index('-num-threads')+1]='2'
write(out/'port-command.json',command)
proof=[argument(x) for x in read(e/'compile-ordinary.json')];proof[1:1]=['-I',str(out),'-DPUBLIC_PROOF_SUBNORMAL']
if lane=='embedded':proof[1:1]=['-DPUBLIC_PROOF_ALL_MODES']
for i,x in enumerate(proof):
 if x.endswith('.swift') and 'enum Mode' in Path(x).read_text():
  p=out/'Proof.swift';p.write_text((root/'Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift').read_text());proof[i]=str(p)
 if x==str(libraries/'libPublicLiftPlanePort.a'):proof[i]=str(out/'libPublicLiftPlanePort.a')
proof[proof.index('-o')+1]=str(out/'proof')
if '-num-threads' in proof:proof[proof.index('-num-threads')+1]='2'
write(out/'proof-command.json',proof)
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
 if code:print(log.read_text()[:14000],flush=True);raise SystemExit(code)
 if label.startswith('runtime'):print(log.read_text()[:2500],flush=True)
run(command,'compile-port',300 if lane=='embedded' else 120)
run(proof,'compile-proof',300 if lane=='embedded' else 120)
product=out/'proof';write(out/'product.json',{str(product):sha(product)})
if lane in ['wasm','embedded']:
 oldruntime=read(e/'runs.json')[0]['runtime'];node=oldruntime[0]
 driver=root/'Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs'
 runtime=[node,str(driver),str(product)]
else:runtime=[str(product)]
for mode in (['all-modes'] if lane=='embedded' else ['ordinary','selections','resources','cancel-entry','cancel-final','unit-regression']):
 assert sha(product)==read(out/'product.json')[str(product)]
 run([*runtime,mode],'runtime-'+mode,120)
write(out/'receipt.json',dict(success=True,lane=lane,parentReceipt=str(e/'receipt.json'),parentSHA256=sha(e/'receipt.json'),production={relative:sha(root/relative)},proofSHA256=sha(root/'Tests/OriginalPublicAcceptanceVerification/OrdinaryPolylineCoonsPlaneProbe.swift'),products={str(product):sha(product),str(out/'libPublicLiftPlanePort.a'):sha(out/'libPublicLiftPlanePort.a'),str(out/'PublicLiftPlanePort.swiftmodule'):sha(out/'PublicLiftPlanePort.swiftmodule')},runs=runs))
