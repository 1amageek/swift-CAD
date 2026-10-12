from pathlib import Path
import json,hashlib,subprocess,time,signal,os,sys,shlex
r=Path.cwd();sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();base=r/'.build/coons-ssi-recovery-20261012/embedded';out=r/'.build/rolling-ssi-20261013/embedded';out.mkdir(parents=True,exist_ok=True)
receipt=json.loads((base/'receipt.json').read_text());native=json.loads((r/'.build/rolling-ssi-20261013/native/objects.json').read_text());changed=set();c=native['command']
for i,x in enumerate(c):
 if x=='-primary-file':changed.add(Path(c[i+1]))
for p,h in receipt['inputs'].items():
 if r/p not in changed:
  if p.endswith('/RationalBivariateAlgebra/ExactRationalCoefficient+SquareRoot.swift'):assert sha(r/'Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/ExactRationalCoefficient+SquareRoot.swift')==h,p
  else:assert sha(r/p)==h,p
for p,h in receipt['products'].items():assert sha(base/p)==h,p
sources=sorted((r/'Sources/CADGeometry').rglob('*.swift'));inputs={str(p):sha(p)for p in sources};swift=c[0];products=base/'build/out/Products/Debug-webassembly-wasm32'
config=subprocess.check_output([str(Path(swift).with_name('swift')),'sdk','configure','--show-configuration','swift-6.4.0-RELEASE_wasm-embedded'],text=True);(out/'sdk.txt').write_text(config);v=dict(x.split(': ',1)for x in config.splitlines()if ': 'in x)
flags=['-module-name','CADGeometry','-package-name','NativeExactRelationVerification','-parse-as-library','-swift-version','6','-enable-testing','-Onone','-D','SWIFT_PACKAGE','-I',str(products),'-module-cache-path',str(out/'cache'),'-target','wasm32-unknown-wasip1','-sdk',v['sdkRootPath'],'-resource-dir',v['swiftResourcesPath'],'-enable-experimental-feature','Embedded','-wmo']
link=['-static-stdlib','-Xlinker','-z','-Xlinker','stack-size=67108864','-Xclang-linker','-resource-dir','-Xclang-linker',str(Path(v['swiftResourcesPath'])/'clang'),'-L',str(Path(v['swiftStaticResourcesPath'])/'wasip1'),'-Xlinker','-lc++','-Xlinker','-lswift_Concurrency','-Xlinker','-lswiftUnicodeDataTables']
def run(command,name,seconds=120,env=None):
 start=time.monotonic();peak=0;reason=None
 with (out/(name+'.log')).open('w')as log:
  p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  while p.poll()is None:
   rows=[list(map(int,x.split()))for x in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()];owned={p.pid}
   for _ in range(20):
    new=owned|{pid for pid,parent,rss in rows if parent in owned}
    if new==owned:break
    owned=new
   memory=sum(rss*1024 for pid,parent,rss in rows if pid in owned);peak=max(peak,memory)
   if time.monotonic()-start>seconds or memory>10737418240:
    reason='wallLimit'if time.monotonic()-start>seconds else'rssLimit'
    for child in owned:
     if child!=p.pid:
      try:os.kill(child,signal.SIGKILL)
      except ProcessLookupError:pass
    try:os.killpg(p.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    p.wait();break
   time.sleep(1)
 record=dict(command=command,exitCode=p.returncode,elapsedSeconds=time.monotonic()-start,peakRSSBytes=peak,wallLimitSeconds=seconds,rssLimitBytes=10737418240,stopReason=reason,inputs=inputs,logSHA256=sha(out/(name+'.log')))
 (out/(name+'.json')).write_text(json.dumps(record,indent=2));print(name,p.returncode,round(record['elapsedSeconds'],3),peak,flush=True)
 if p.returncode:print((out/(name+'.log')).read_text()[-4000:]);raise SystemExit(p.returncode)
rsp=out/'sources.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in sources)+'\n')
objectMap={}
for source in sources:
 target=out/'owner-objects'/source.relative_to(r/'Sources/CADGeometry').with_suffix('.o');target.parent.mkdir(parents=True,exist_ok=True)
 objectMap[str(source)]={'object':str(target)}
mapPath=out/'owner-output-map.json';mapPath.write_text(json.dumps(objectMap,indent=2))
jobPath=out/'frontend-jobs.json'
if not jobPath.exists():
 driver=[swift,*flags,'-num-threads','2','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'-c','-output-file-map',str(mapPath),'@'+str(rsp),'-driver-print-jobs']
 printed=subprocess.check_output(driver,text=True,timeout=30)
 jobs=[shlex.split(line)for line in printed.splitlines()if line.strip()]
 assert len(jobs)==2
 jobPath.write_text(json.dumps(jobs,indent=2))
jobs=json.loads(jobPath.read_text())
module=jobs[1].copy()
for flag in ['-emit-module-doc-path','-emit-module-source-info-path']:
 if flag in module:
  index=module.index(flag);del module[index:index+2]
first=next(i for i,x in enumerate(module)if x.endswith('.swift'));module=[x for x in module if not x.endswith('.swift')];module.insert(first,'@'+str(rsp))
if (out/'frontend-module.json').exists():
 proof=json.loads((out/'frontend-module.json').read_text());assert proof['exitCode']==0 and proof['inputs']==inputs
else:run(module,'frontend-module',1200)
fileList=out/'owner-sources.list';fileList.write_text('\n'.join(str(p)for p in sources)+'\n')
outputList=out/'owner-outputs.list';outputList.write_text('\n'.join(v['object']for v in objectMap.values())+'\n')
supplementary=out/'owner-supplementary.json';supplementary.write_text(json.dumps({str(p):{}for p in sources}))
objectJob=jobs[0].copy()
for flag,value in [('-filelist',fileList),('-output-filelist',outputList),('-supplementary-output-file-map',supplementary)]:objectJob[objectJob.index(flag)+1]=str(value)
objectJob[objectJob.index('-num-threads')+1]='1'
run(objectJob,'frontend-objects',1200)
objects=[Path(v['object'])for v in objectMap.values()]+[p for n in ['CADCore','HashTreeCollections','InternalCollectionsUtilities']for p in (products/(n+'.objlib')).rglob('*.o')]
checks={str(p):sha(p)for p in objects+[out/'CADGeometry.swiftmodule']};fixture=r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIAcceptance.swift';checks[str(fixture)]=sha(fixture)
objrsp=out/'link.rsp';objrsp.write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n');executable=out/'Acceptance.wasm';fflags=flags.copy();fflags[fflags.index('-module-name')+1]='RollingSSIProof';fflags[fflags.index('-I'):fflags.index('-I')]=['-I',str(out)]
text=fixture.read_text();imports=text[:text.index('@main')];start=text.index('    typealias Base');oracle=text.index('    static func oracle(');failure=text.index('    static func failure(')
split=out/'parallel-fixture';split.mkdir(exist_ok=True)
parts=[imports+'extension RollingPlaneSSIAcceptance {\n'+text[start:oracle]+'}\n',imports+'extension RollingPlaneSSIAcceptance {\n'+text[oracle:failure]+'}\n',imports+'@main struct RollingPlaneSSIAcceptance {\n'+text[failure:]]
paths=[]
for name,body in zip(['Query','Oracle','Entry'],parts):
 p=split/(name+'.swift');p.write_text(body);paths.append(p);checks[str(p)]=sha(p)
run([swift,*fflags,'-num-threads','2','-Xfrontend','-disable-cmo',*link,*[str(p)for p in paths],'@'+str(objrsp),'-o',str(executable)],'fixture-parallel');checks[str(executable)]=sha(executable)
(out/'premises.json').write_text(json.dumps(dict(checks=checks,inputs=inputs,baseReceiptSHA256=sha(base/'receipt.json'),sdkIdentifier='swift-6.4.0-RELEASE_wasm-embedded'),indent=2))
for group in sys.argv[1:]:
 for p,h in checks.items():assert sha(p)==h,p
 run(['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIWASI.mjs'),str(executable)],group,env=dict(os.environ,CAD_PROOF_GROUP=group))
for p,h in inputs.items():assert sha(p)==h,p
