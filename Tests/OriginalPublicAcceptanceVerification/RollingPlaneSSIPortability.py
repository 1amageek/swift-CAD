from pathlib import Path
import json,hashlib,subprocess,time,os,signal,sys
r=Path.cwd();lane=sys.argv[1];sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();base=r/'.build/coons-ssi-recovery-20261012'/lane;out=r/'.build/rolling-ssi-20261013'/lane;out.mkdir(parents=True,exist_ok=True)
meta=json.loads((r/'.build/rolling-ssi-20261013/native/objects.json').read_text());primary=[];cmd=meta['command'];idx=0
while '-primary-file' in cmd[idx:]:
 idx=cmd.index('-primary-file',idx);primary.append(Path(cmd[idx+1]));idx+=2
receipt=json.loads((base/'receipt.json').read_text())
for p,h in receipt['inputs'].items():
 if r/p not in primary:
  if p.endswith('/RationalBivariateAlgebra/ExactRationalCoefficient+SquareRoot.swift'):assert sha(r/'Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/ExactRationalCoefficient+SquareRoot.swift')==h,p
  else:assert sha(r/p)==h,p
for p,h in receipt['products'].items():assert sha(base/p)==h,p
sources=sorted((r/'Sources/CADGeometry').rglob('*.swift'));inputs={str(p):sha(p)for p in sources};swift=cmd[0]
portable=lane!='asan';products=base/'build/out/Products'/('Debug-webassembly-wasm32'if portable else'Debug')
flags=['-module-name','CADGeometry','-package-name','NativeExactRelationVerification','-parse-as-library','-swift-version','6','-enable-testing','-Onone','-D','SWIFT_PACKAGE','-I',str(products),'-module-cache-path',str(out/'cache')]
link=[]
if portable:
 config=subprocess.check_output([str(Path(swift).with_name('swift')),'sdk','configure','--show-configuration','swift-6.4.0-RELEASE_wasm'],text=True);v=dict(x.split(': ',1)for x in config.splitlines()if ': 'in x);flags+=['-target','wasm32-unknown-wasip1','-sdk',v['sdkRootPath'],'-resource-dir',v['swiftResourcesPath']];link=['-static-stdlib','-Xlinker','-z','-Xlinker','stack-size=67108864','-Xclang-linker','-resource-dir','-Xclang-linker',str(Path(v['swiftResourcesPath'])/'clang')]
else:
 sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip();flags+=['-target','arm64-apple-macosx15.0','-sdk',sdk,'-sanitize=address']
def run(command,name,env=None):
 start=time.monotonic()
 with (out/(name+'.log')).open('w')as log:
  p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  try:code=p.wait(timeout=120)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
 record=dict(command=command,exitCode=code,elapsedSeconds=time.monotonic()-start,inputs=inputs,logSHA256=sha(out/(name+'.log')))
 (out/(name+'.json')).write_text(json.dumps(record,indent=2));print(lane,name,code,round(record['elapsedSeconds'],3),flush=True)
 if code:print((out/(name+'.log')).read_text()[-2500:]);raise SystemExit(code)
reuse=os.environ.get('ROLLING_REUSE')=='1'
if reuse:
 for name in ['module','objects']:
  proof=json.loads((out/(name+'.json')).read_text());assert proof['exitCode']==0 and proof['inputs']==inputs
 for p,h in json.loads((out/'premises.json').read_text())['checks'].items():
  if not p.endswith('RollingPlaneSSIAcceptance.swift') and not p.endswith('Acceptance') and not p.endswith('Acceptance.wasm'):assert sha(p)==h,p
rsp=out/'sources.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in sources)+'\n');
if not reuse:run([swift,*flags,'-wmo','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'@'+str(rsp)],'module')
other=out/'other.rsp';other.write_text('\n'.join(json.dumps(str(p))for p in sources if p not in primary)+'\n');pflags=[];outputs=[]
for p in primary:pflags+=['-primary-file',str(p)];outputs+=['-o',str(out/(p.stem+'.o'))]
if not reuse:run([swift,'-frontend','-c',*flags,*pflags,'@'+str(other),*outputs],'objects')
objmap=json.loads(next((base/'build/out/Intermediates.noindex').rglob('CADGeometry-OutputFileMap.json')).read_text());objects=[]
for p,d in objmap.items():
 if p:
  new=out/(Path(p).stem+'.o');objects.append(new if new.exists() and Path(p).stem in {q.stem for q in primary}else Path(d['object']))
for p in primary:
 q=out/(p.stem+'.o')
 if q not in objects:objects.append(q)
if portable:objects += [p for n in ['CADCore','HashTreeCollections','InternalCollectionsUtilities']for p in (products/(n+'.objlib')).rglob('*.o')]
else:objects += [products/(n+'.o')for n in ['CADCore','HashTreeCollections','InternalCollectionsUtilities']]
checks={str(p):sha(p)for p in objects+[out/'CADGeometry.swiftmodule']};fixture=r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIAcceptance.swift';checks[str(fixture)]=sha(fixture)
objrsp=out/'link.rsp';objrsp.write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n');executable=out/('Acceptance.wasm'if portable else'Acceptance');fflags=[x for x in flags];fflags[fflags.index("-module-name")+1]="RollingSSIProof"
fflags[fflags.index('-I'):fflags.index('-I')]=['-I',str(out)]
run([swift,*fflags,*link,str(fixture),'@'+str(objrsp),'-o',str(executable)],'fixture');checks[str(executable)]=sha(executable)
(out/'premises.json').write_text(json.dumps(dict(checks=checks,baseReceiptSHA256=sha(base/'receipt.json'),inputs=inputs),indent=2))
for group in sys.argv[2:]:
 for p,h in checks.items():assert sha(p)==h,p
 runtime=['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIWASI.mjs'),str(executable)]if portable else[str(executable)]
 run(runtime,group,dict(os.environ,CAD_PROOF_GROUP=group))
for p,h in inputs.items():assert sha(p)==h,p
