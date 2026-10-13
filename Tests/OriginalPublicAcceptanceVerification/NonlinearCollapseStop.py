from pathlib import Path
import hashlib,json,os,signal,subprocess,time
r=Path.cwd();lane='native';out=r/'.build/nonlinear-collapse-20261013/red';out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-IMAGE-PERIOD-01'
sources=json.loads((e/'source-premises.json').read_text());products=json.loads((e/'products.json').read_text())
for p,h in sources.items():assert sha(r/p)==h,p
for p,h in products.items():assert sha(p)==h,p
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
base=r/'.build/native-identity-current-20261013-v2/native/compile.json'
c=[v for v in json.loads(base.read_text())['command']if not v.endswith('.swift')]
fixture=r/'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.swift';c.insert(next(i for i,v in enumerate(c)if v.startswith('@')),str(fixture));exe=out/'Proof';c[-1]=str(exe)
run(c,'compile');run([str(exe)],'red')
(out/'premises.json').write_text(json.dumps(dict(sources=sources,products=products,fixtureSHA256=sha(fixture),executableSHA256=sha(exe)),indent=2)+'\n')
