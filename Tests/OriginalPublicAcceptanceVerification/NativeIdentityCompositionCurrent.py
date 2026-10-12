"""Close F1 on actual current Geometry with one fresh issuer body and unchanged oracle."""
from pathlib import Path
import hashlib,json,os,re,signal,subprocess,sys,time
r=Path.cwd();lane=sys.argv[1];assert lane in ['native','asan','wasm','embedded']
base=r/'.build/periodic-offset-cs-20261013'/lane;out=r/'.build/native-identity-current-20261013-v2'/lane;out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-OFFSET-PERIODIC-ZERO-GEOM-01'
sources=json.loads((e/'source-premises.json').read_text());products=json.loads((e/'products.json').read_text())
for p,h in sources.items():assert sha(r/p)==h,p
for p,h in products.items():assert sha(p)==h,p
record=json.loads((e/'accepted'/lane/'premises.json').read_text());checks=dict(record['checks'])
fixture=r/'Tests/OriginalPublicAcceptanceVerification/NativeIdentityCompositionCurrent.swift';checks[str(fixture)]=sha(fixture)
original=r/'Tests/OriginalPublicAcceptanceVerification/NativeIdentityCompositionAcceptance.swift'
text=original.read_text();start=text.index('#if canImport(Darwin)');expected=('import CADCore\n@testable import CADGeometry\n'+text[start:]).replace('NativeDeclaredWholeEdgeSelf.','')
assert fixture.read_text()==expected,'Only imports/type qualifiers may differ from the frozen oracle'
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
issuer=r/'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift'
objects=[Path(p)for p in checks if p.endswith('.o')]
if lane!='embedded':
    c=json.loads((base/'objects.json').read_text())['command'];prefix=c[:c.index('-primary-file')]
    others=out/'others.rsp';others.write_text('\n'.join(json.dumps(str(r/p))for p in sorted(sources)if p.startswith('Sources/CADGeometry/')and r/p!=issuer)+'\n')
    fresh=out/'DefaultOriginalParameterIdentityIssuer.o'
    run([*prefix,'-primary-file',str(issuer),'@'+str(others),'-o',str(fresh)],'fresh-issuer')
    replaced=[p for p in objects if p.stem in ['DefaultOriginalParameterIdentityIssuer','DefaultOriginalParameterIdentityIssuer.swift']];assert len(replaced)==1,replaced
    objects=[fresh if p==replaced[0]else p for p in objects];checks[str(fresh)]=sha(fresh)
else:
    d=json.loads((base/'objects.json').read_text());assert d['exitCode']==0 and d['inputs'][str(issuer)]==sha(issuer)
    (out/'embedded-current-generation.json').write_text(json.dumps(dict(receipt=str(base/'objects.json'),receiptSHA256=sha(base/'objects.json'),issuerSHA256=sha(issuer),scope='Current full WMO generation, no regeneration'),indent=2)+'\n')
rsp=out/'objects.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n')
c=json.loads((base/('fixture.json')).read_text())['command']
if lane=='native':
    c=[str(fixture)if x.endswith('PeriodicOffsetCSStop.swift')else x for x in c]
else:
    c=[x for x in c if not x.endswith('.swift')];i=next(i for i,x in enumerate(c)if x.startswith('@'));c.insert(i,str(fixture))
if lane=='embedded':
    t=fixture.read_text();head=t[:t.index('@main')];a=t.index('    typealias Base');b=t.index('    nonisolated static func invariants(');d=t.index('    struct PublicationAdmission');f=t.index('    nonisolated static func run()')
    pieces=[head+'extension NativeIdentityCompositionAcceptance {\n'+t[a:b]+'}\n',head+'extension NativeIdentityCompositionAcceptance {\n'+t[b:d]+'}\n',head+'extension NativeIdentityCompositionAcceptance {\n'+t[d:f]+'}\n',head+'@main struct NativeIdentityCompositionAcceptance {\n'+t[f:]]
    split=out/'fixture';split.mkdir(exist_ok=True);paths=[]
    for name,body in zip(['Query','Oracle','Controls','Entry'],pieces):
        p=split/(name+'.swift');p.write_text(body);paths.append(str(p));checks[str(p)]=sha(p)
    i=c.index(str(fixture));c[i:i+1]=paths
executable=out/('Proof'if lane in ['native','asan']else'Proof.wasm')
c=[('@'+str(rsp))if x.startswith('@')else x for x in c];c[-1]=str(executable)
run(c,'compile',1200 if lane=='embedded'else 120);checks[str(executable)]=sha(executable)
checks[str(issuer)]=sha(issuer)
wasi=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs';assert sha(wasi)==wasi.stem;checks[str(wasi)]=sha(wasi)
(out/'premises.json').write_text(json.dumps(dict(checks=checks,sources=sources,priorProductsSHA256=sha(e/'products.json'),originalFixtureSHA256=sha(original),fixtureSHA256=sha(fixture)),indent=2)+'\n')
counts=None
for group in ['complete','controls','exact','work','storage','cancel']:
    for p,h in checks.items():assert sha(p)==h,p
    argument=group if counts is None or group=='controls'else group+':'+':'.join(counts)
    command=[str(executable),argument]if lane in ['native','asan']else['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'),str(executable),argument]
    log=run(command,group,env=dict(os.environ,CAD_PROOF_GROUP=argument))
    expected={'complete':'PASS every terminal raw/refined iff','controls':'PASS depth3/count5 exact readmission','exact':'PASS independent prepared query exact workN/storageN','work':'PASS workN-1 exact typed work refusal','storage':'PASS storageN-1 exact typed storage refusal','cancel':'PASS entry and final-publication checkpoint cancellation'}
    assert expected[group]in log and 'OBSERVED STOP'not in log,group
    if group=='controls':counts=re.search(r'METRIC preparedQueryBoundary (\d+) (\d+) (\d+)',log).groups()
for p,h in checks.items():assert sha(p)==h,p
(out/'summary.json').write_text(json.dumps(dict(status='PASS',lane=lane,groups=['complete','controls','exact','work','storage','cancel'],queryBoundary=list(map(int,counts)),issuerSHA256=sha(issuer),freshIssuerBody=lane!='embedded',premisesSHA256=sha(out/'premises.json')),indent=2)+'\n')
