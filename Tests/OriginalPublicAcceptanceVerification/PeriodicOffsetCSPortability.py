"""Compile actual changed Geometry paths against admitted rolling-cell dependencies."""
from pathlib import Path
import hashlib,json,os,shlex,signal,subprocess,sys,time
r=Path.cwd();lane=sys.argv[1];groups=sys.argv[2:];sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
base=r/'.build/rolling-ssi-20261013'/lane;out=r/'.build/periodic-offset-cs-20261013'/lane;out.mkdir(parents=True,exist_ok=True)
primaryCommand=json.loads((r/'.build/periodic-offset-cs-20261013/native/objects.json').read_text())['command']
primary={Path(primaryCommand[i+1])for i,x in enumerate(primaryCommand)if x=='-primary-file'}
old=json.loads((base/('frontend-module.json'if lane=='embedded'else'module.json')).read_text())
for p,h in old['inputs'].items():
 if Path(p)not in primary:assert sha(p)==h,p
baseline=json.loads((base/'premises.json').read_text())
for p,h in baseline['checks'].items():assert sha(p)==h,p
sources=sorted((r/'Sources/CADGeometry').rglob('*.swift'));inputs={str(p):sha(p)for p in sources}
swift='/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc'
def run(command,name,seconds=120,env=None):
 start=time.monotonic();peak=0;reason=None
 with (out/(name+'.log')).open('w')as log:
  p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  while p.poll()is None:
   rows=[list(map(int,line.split()))for line in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()];owned={p.pid}
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
   time.sleep(0.5)
 record=dict(command=command,exitCode=p.returncode,elapsedSeconds=time.monotonic()-start,peakRSSBytes=peak,wallLimitSeconds=seconds,rssLimitBytes=10737418240,stopReason=reason,inputs=inputs,logSHA256=sha(out/(name+'.log')))
 (out/(name+'.json')).write_text(json.dumps(record,indent=2));print(lane,name,p.returncode,round(record['elapsedSeconds'],3),peak,flush=True)
 if p.returncode:print((out/(name+'.log')).read_text()[-5000:]);raise SystemExit(p.returncode)
link=[]
if lane=='asan':
 c=old['command'];flags=c[1:c.index('-wmo')]
else:
 sdk='swift-6.4.0-RELEASE_wasm'+('-embedded'if lane=='embedded'else'')
 config=subprocess.check_output([str(Path(swift).with_name('swift')),'sdk','configure','--show-configuration',sdk],text=True,timeout=30);(out/'sdk.txt').write_text(config);v=dict(line.split(': ',1)for line in config.splitlines()if ': 'in line)
 dep=old['command'][old['command'].index('-I')+1]
 flags=['-module-name','CADGeometry','-package-name','NativeExactRelationVerification','-parse-as-library','-swift-version','6','-enable-testing','-Onone','-D','SWIFT_PACKAGE','-I',dep,'-module-cache-path',str(out/'cache'),'-target','wasm32-unknown-wasip1','-sdk',v['sdkRootPath'],'-resource-dir',v['swiftResourcesPath']]
 link=['-static-stdlib','-Xlinker','-z','-Xlinker','stack-size=67108864','-Xclang-linker','-resource-dir','-Xclang-linker',str(Path(v['swiftResourcesPath'])/'clang')]
 if lane=='embedded':
  flags+=['-enable-experimental-feature','Embedded','-wmo'];link+=['-L',str(Path(v['swiftStaticResourcesPath'])/'wasip1'),'-Xlinker','-lc++','-Xlinker','-lswift_Concurrency','-Xlinker','-lswiftUnicodeDataTables']
flags[flags.index('-module-cache-path')+1]=str(out/'cache')
rsp=out/'sources.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in sources)+'\n')
reuse=os.environ.get('PERIODIC_OFFSET_REUSE')=='1'
if reuse:
 for stage in ['module','objects']:
  d=json.loads((out/(stage+'.json')).read_text());assert d['exitCode']==0 and d['inputs']==inputs
if lane=='embedded':
 objectMap={str(p):{'object':str(out/'objects'/p.relative_to(r/'Sources/CADGeometry').with_suffix('.o'))}for p in sources}
 for d in objectMap.values():Path(d['object']).parent.mkdir(parents=True,exist_ok=True)
 mapPath=out/'output-map.json';mapPath.write_text(json.dumps(objectMap))
 driver=[swift,*flags,'-num-threads','2','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'-c','-output-file-map',str(mapPath),'@'+str(rsp),'-driver-print-jobs']
 jobs=[shlex.split(line)for line in subprocess.check_output(driver,text=True,timeout=30).splitlines()if line.strip()];assert len(jobs)==2
 module=jobs[1].copy()
 for flag in ['-emit-module-doc-path','-emit-module-source-info-path']:
  i=module.index(flag);del module[i:i+2]
 first=next(i for i,x in enumerate(module)if x.endswith('.swift'));module=[x for x in module if not x.endswith('.swift')];module.insert(first,'@'+str(rsp))
 fileList=out/'sources.list';fileList.write_text('\n'.join(str(p)for p in sources)+'\n')
 outputList=out/'outputs.list';outputList.write_text('\n'.join(d['object']for d in objectMap.values())+'\n')
 supplementary=out/'supplementary.json';supplementary.write_text(json.dumps({str(p):{}for p in sources}))
 objectJob=jobs[0].copy()
 for flag,value in [('-filelist',fileList),('-output-filelist',outputList),('-supplementary-output-file-map',supplementary)]:objectJob[objectJob.index(flag)+1]=str(value)
 objectJob[objectJob.index('-num-threads')+1]='1'
 if not reuse:run(module,'module',1200);run(objectJob,'objects',1200)
 objects=[Path(d['object'])for d in objectMap.values()]
 objects += [Path(p)for p in baseline['checks']if p.endswith('.o')and any('/'+n+'.objlib/'in p for n in ['CADCore','HashTreeCollections','InternalCollectionsUtilities'])]
else:
 if not reuse:run([swift,*flags,'-wmo','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'@'+str(rsp)],'module')
 others=out/'others.rsp';others.write_text('\n'.join(json.dumps(str(p))for p in sources if p not in primary)+'\n');args=[];outputs=[]
 for p in sorted(primary):args+=['-primary-file',str(p)];outputs+=['-o',str(out/(p.stem+'.o'))]
 if not reuse:run([swift,'-frontend','-c',*flags,*args,'@'+str(others),*outputs],'objects')
 objects=[out/(Path(p).stem+'.o')if Path(p).stem in {s.stem for s in primary}else Path(p)for p in baseline['checks']if p.endswith('.o')]
 for p in sorted(primary):
  obj=out/(p.stem+'.o')
  if obj not in objects:objects.append(obj)
checks={str(p):sha(p)for p in objects+[out/'CADGeometry.swiftmodule']}
fixture=r/'Tests/OriginalPublicAcceptanceVerification/PeriodicOffsetCSAcceptance.swift';checks[str(fixture)]=sha(fixture)
objrsp=out/'link.rsp';objrsp.write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n')
executable=out/('Acceptance'if lane=='asan'else'Acceptance.wasm');fflags=flags.copy();fflags[fflags.index('-module-name')+1]='PeriodicOffsetCSProof';fflags[fflags.index('-I'):fflags.index('-I')]=['-I',str(out)]
paths=[fixture]
if lane=='embedded':
 text=fixture.read_text();imports=text[:text.index('@main')];start=text.index('    typealias Base');oracle=text.index('    static func oracle(');runStart=text.index('    static func run(')
 split=out/'fixture-sources';split.mkdir(exist_ok=True)
 parts=[imports+'extension PeriodicOffsetCSAcceptance {\n'+text[start:oracle]+'}\n',imports+'extension PeriodicOffsetCSAcceptance {\n'+text[oracle:runStart]+'}\n',imports+'@main struct PeriodicOffsetCSAcceptance {\n'+text[runStart:]]
 paths=[]
 for name,body in zip(['Query','Oracle','Entry'],parts):
  path=split/(name+'.swift');path.write_text(body);paths.append(path);checks[str(path)]=sha(path)
 fflags+=['-num-threads','2','-Xfrontend','-disable-cmo']
run([swift,*fflags,*link,*[str(p)for p in paths],'@'+str(objrsp),'-o',str(executable)],'fixture',1200 if lane=='embedded' else 120)
checks[str(executable)]=sha(executable);(out/'premises.json').write_text(json.dumps(dict(checks=checks,inputs=inputs,basePremisesSHA256=sha(base/'premises.json')),indent=2))
for group in groups:
 for p,h in checks.items():assert sha(p)==h,p
 command=[str(executable)]if lane=='asan'else['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIWASI.mjs'),str(executable)]
 run(command,group,env=dict(os.environ,CAD_PROOF_GROUP=group))
 assert ('PASS '+group)in(out/(group+'.log')).read_text(),(lane,group)
for p,h in inputs.items():assert sha(p)==h,p
