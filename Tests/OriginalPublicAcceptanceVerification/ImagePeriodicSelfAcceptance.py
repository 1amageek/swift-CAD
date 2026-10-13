"""Use admitted current Geometry and fresh identity products for the singular public cell."""
from pathlib import Path
import hashlib,json,os,re,signal,subprocess,sys,time
r=Path.cwd();lane=sys.argv[1];assert lane in ['native','asan','wasm','embedded']
base=r/'.build/native-identity-current-20261013-v2'/lane;out=r/'.build/image-periodic-self-20261013'/lane;out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/F1/current'
sources=json.loads((e/'source-premises.json').read_text());products=json.loads((e/'products.json').read_text())
for p,h in sources.items():
    if p!='Sources/CADGeometry/NativeExactRelations/DefaultNativeExactRelationFamilyResolver+Symbolic.swift':assert sha(r/p)==h,p
for p,h in products.items():assert sha(p)==h,p
checks=dict(json.loads((e/lane/'premises.json').read_text())['checks'])
common=r/'Tests/OriginalPublicAcceptanceVerification/NativeIdentityCompositionCurrent.swift'
helper=out/'Common.swift';text=common.read_text();assert text.count('@main struct')==1
helper.write_text(text.replace('@main struct','struct',1));checks[str(common)]=sha(common);checks[str(helper)]=sha(helper)
fixture=r/'Tests/OriginalPublicAcceptanceVerification/ImagePeriodicSelfAcceptance.swift';checks[str(fixture)]=sha(fixture)
def run(command,name,seconds=120,env=None):
    start=time.monotonic();peak=0;reason=None
    with (out/(name+'.log')).open('w')as log:
        p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
        while p.poll()is None:
            rows=[list(map(int,line.split()))for line in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()];owned={p.pid}
            while True:
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
            time.sleep(.25)
    d=dict(command=command,exitCode=p.returncode,elapsedSeconds=time.monotonic()-start,peakRSSBytes=peak,wallLimitSeconds=seconds,rssLimitBytes=10737418240,stopReason=reason,logSHA256=sha(out/(name+'.log')))
    (out/(name+'.json')).write_text(json.dumps(d,indent=2)+'\n');print(lane,name,p.returncode,round(d['elapsedSeconds'],3),flush=True)
    if p.returncode:print((out/(name+'.log')).read_text()[-4000:]);raise SystemExit(p.returncode)
    return (out/(name+'.log')).read_text()
c=json.loads((base/'compile.json').read_text())['command'];c=[x for x in c if not x.endswith('.swift')]
port_sources=[r/'Sources/CADGeometry/OriginalSurfaceEmbedding'/name for name in ['OriginalAffinePeriodicSelfContactQuerying.swift','OriginalAffinePeriodicSelfContacts.swift','DefaultOriginalAffinePeriodicSelfContactQuery.swift']]
port_sources += [r/'Sources/CADGeometry/NativeExactRelations'/name for name in ['DefaultNativeExactRelationFamilyResolver+Symbolic.swift','NativeExactSymbolicSurfacePredicateFamily.swift','NativeExactSymbolicSurfacePredicateCompiling.swift']]
for p in port_sources:checks[str(p)]=sha(p)
module=out/'ImagePeriodicSelfPort.swiftmodule';object_file=out/'ImagePeriodicSelfPort.o'
port=[];index=0
while index<len(c):
    option=c[index]
    if option in ['-o','-module-name','-Xlinker','-Xclang-linker','-L']:
        index+=2;continue
    if option.startswith('@') or option in ['-static-stdlib']:
        index+=1;continue
    port.append(option);index+=1
if '-num-threads' in port:
    i=port.index('-num-threads');del port[i:i+2]
port+=['-module-name','ImagePeriodicSelfPort','-D','ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION','-whole-module-optimization','-emit-module','-emit-object','-emit-module-path',str(module),'-o',str(object_file),*[str(p)for p in port_sources]]
run(port,'port',1200 if lane=='embedded'else 120)
checks[str(module)]=sha(module);checks[str(object_file)]=sha(object_file)
i=next(i for i,x in enumerate(c)if x.startswith('@'));c[i:i]=['-I',str(out),str(object_file),str(helper),str(fixture)]
executable=out/('Proof'if lane in ['native','asan']else'Proof.wasm');c[-1]=str(executable)
run(c,'compile',1200 if lane=='embedded'else 120);checks[str(executable)]=sha(executable)
wasi=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs';assert sha(wasi)==wasi.stem;checks[str(wasi)]=sha(wasi)
(out/'premises.json').write_text(json.dumps(dict(checks=checks,sources=sources,inheritedProductsSHA256=sha(e/'products.json'),commonSourceSHA256=sha(common),fixtureSHA256=sha(fixture)),indent=2)+'\n')
markers={'controls':'PASS nonperiodic contact, all81 mixed lifts, huge cycles, owner/limits, COW lifetime and later cancel','complete':'PASS complete81 symbolic raw equality and49 exact scoped parent shifts','requests':'PASS exact open/closed request, missing raw coverage and singular spatial rejection','empty':'PASS complete empty parent restriction and final-publication cancellation','compiler':'PASS compiler exactN/N-1, all-pair limits and entry/final cancel','exact':'PASS exact query workN/storageN','work':'PASS workN-1 typed refusal','storage':'PASS storageN-1 typed refusal','cancel':'PASS entry/final-publication query cancellation'}
counts=None
for group in markers:
    for p,h in checks.items():assert sha(p)==h,p
    argument=group if group not in ['exact','work','storage','cancel']else group+':'+':'.join(counts)
    command=[str(executable)]if lane in ['native','asan']else['/usr/local/bin/node',str(wasi),str(executable),argument]
    log=run(command,group,env=dict(os.environ,CAD_PROOF_GROUP=argument))
    assert markers[group]in log and 'OBSERVED STOP'not in log,group
    if group=='controls':counts=re.search(r'METRIC preparedQueryBoundary (\d+) (\d+) (\d+)',log).groups()
for p,h in sources.items():
    if p!='Sources/CADGeometry/NativeExactRelations/DefaultNativeExactRelationFamilyResolver+Symbolic.swift':assert sha(r/p)==h,p
(out/'summary.json').write_text(json.dumps(dict(status='PASS',lane=lane,groups=list(markers),queryBoundary=counts,premisesSHA256=sha(out/'premises.json')),indent=2)+'\n')
