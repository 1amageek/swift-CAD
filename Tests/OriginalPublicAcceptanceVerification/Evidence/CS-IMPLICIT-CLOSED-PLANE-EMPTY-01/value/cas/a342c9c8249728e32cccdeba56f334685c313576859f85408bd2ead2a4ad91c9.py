#!/usr/bin/env python3
"""Prepare or execute three generation-bound primaries and one ordinary CS observation."""
import argparse, hashlib, json, os, resource, signal, subprocess, time, shlex
from pathlib import Path
ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
OUT = ROOT / '.build/cs-implicit-closed-value-native-20261013-v2'
PRIOR = ROOT / '.build/cs-implicit-closed-connection-native-20261013-v1'
CELL = 'CS-IMPLICIT-CLOSED-PLANE-EMPTY-01'
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def save(name,value): (OUT/name).write_text(json.dumps(value,indent=2)+'\n')
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=5).strip()
def prepare():
    assert not (OUT/'execution-started.json').exists(), 'Dedicated observation already started'
    OUT.mkdir(parents=True,exist_ok=True)
    previous=read(PRIOR/'premises.json'); inventory=read(PRIOR/'generation-inventory.json')
    durable=ROOT/'Tests/OriginalPublicAcceptanceVerification/Evidence'/CELL/'connection'
    assert sha(durable/'summary.json')=='53935493088f2cde3b6a8305cd30930126de1f3c5d911335bd031614609f6841'
    checks=dict(previous['checks'])
    for path in [PRIOR/'premises.json',PRIOR/'generation-inventory.json',durable/'summary.json',durable/'manifest.json',durable/'receipt.json']:
        checks[str(path)]=sha(path)
    selected=dict(previous['selectedSources'])
    selected['OriginalCurveTaylorComposition.swift']='e7b5d45ac41f8dd59332855a594fd7405a22f10dac429474c17e3000e5c30f13'
    outputs={}; snapshots={}
    (OUT/'selected').mkdir(exist_ok=True)
    for name,digest in selected.items():
        current=ROOT/'Sources/CADGeometry'/('OriginalHigherCurveJets/'+name if name=='OriginalCurveTaylorComposition.swift' else name)
        assert sha(current)==digest
        snapshot=OUT/'selected'/name;snapshot.write_bytes(current.read_bytes())
        checks[str(current)]=digest;checks[str(snapshot)]=digest
        snapshots[name]=str(snapshot);outputs[name]=str(OUT/(Path(name).stem+'.o'))
    sourceBindings=[]
    for old in inventory['sourceBindings']:
        value=dict(old);name=Path(value['generationInput']).name
        if name in snapshots:
            value.update(compiledInput=snapshots[name],compiledSHA256=selected[name],primary=True)
        sourceBindings.append(value)
    assert len(sourceBindings)==1651 and sum(v['primary']for v in sourceBindings)==3
    filelist=OUT/'generation-filelist-with-selected3.txt'
    filelist.write_text(''.join(v['compiledInput']+'\n'for v in sourceBindings))
    checks[str(filelist)]=sha(filelist)
    job=read(PRIOR/'primary2-command.json'); result=[];i=0
    while i<len(job):
        if job[i] in {'-primary-file','-o'}:i+=2;continue
        if job[i]=='-filelist':result.extend([job[i],str(filelist)]);i+=2;continue
        if job[i]=='-module-cache-path':result.extend([job[i],str(OUT/'primary-module-cache')]);i+=2;continue
        result.append(job[i]);i+=1
    for path in snapshots.values():result.extend(['-primary-file',path])
    for path in outputs.values():result.extend(['-o',path])
    save('primary3-command.json',result)
    archive=OUT/'libCachedCADGeometryValue.a'; archiveInputs=[];objectBindings=[]
    for old in inventory['objectBindings']:
        value=dict(old);name=Path(value['generationObject']).stem+'.swift'
        value.update(archiveInput=outputs.get(name,value['generationObject']),replaced=name in outputs)
        archiveInputs.append(value['archiveInput']);objectBindings.append(value)
    assert len(archiveInputs)==1651 and sum(v['replaced']for v in objectBindings)==3
    save('archive-command.json',['ar','-rcs',str(archive),*archiveInputs])
    fixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitClosedPlaneEmptyValueObservation.swift'
    oldfixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitClosedPlaneEmptyConnectionAcceptance.swift'
    oldproof=(PRIOR/'Proof.swift').read_bytes();assert oldproof.endswith(oldfixture.read_bytes())
    proof=OUT/'Proof.swift';proof.write_bytes(oldproof[:-len(oldfixture.read_bytes())]+fixture.read_bytes())
    command=read(PRIOR/'compile-link-command.json')
    command[command.index(str(PRIOR/'Proof.swift'))]=str(proof)
    command[command.index(previous['freshArchive'])]=str(archive)
    command[command.index('-module-cache-path')+1]=str(OUT/'upper-module-cache')
    command[command.index('-module-name')+1]='ImplicitClosedPlaneEmptyValueObservation'
    command[command.index('-o')+1]=str(OUT/'ValueObservation')
    assert sum(v.endswith('.swift')for v in command)==58 and sum(v.endswith('.a')for v in command)==14
    save('compile-link-command.json',command)
    for path in [fixture,proof,Path(__file__).resolve(),ROOT/'Sources/CADGeometry/OriginalHigherCurveJets/DESIGN.md']:
        checks[str(path)]=sha(path)
    for name in ['primary3-command.json','archive-command.json','compile-link-command.json']:
        checks[str(OUT/name)]=sha(OUT/name)
    save('generation-inventory.json',dict(generationReceipt=inventory['generationReceipt'],
        metadataAuthority=inventory['metadataAuthority'],sourceBindings=sourceBindings,
        objectBindings=objectBindings,recoveredGenerationSources=inventory['recoveredGenerationSources'],
        reusedFrozenInventory=dict(path=str(PRIOR/'generation-inventory.json'),sha256=sha(PRIOR/'generation-inventory.json'))))
    checks[str(OUT/'generation-inventory.json')]=sha(OUT/'generation-inventory.json')
    premises=dict(previous)
    premises.update(state='prepared-pending-root-execution-GO',checks=checks,selectedSources=selected,
        freshOutputs=outputs,freshArchive=str(archive),executable=str(OUT/'ValueObservation'),
        productionPrimaryBodies=3,reusedObjectBodies=1648,
        controls=['scaledParameter constant coefficient bit identity for [0,1]/singleton4 and gains1/-2/0; higher coefficients previous outward power operations',
          'strict prepared surface outside support typed rejection','actual original closed4 constructor once'],
        priorConnectionObservation=dict(path=str(durable/'summary.json'),sha256=sha(durable/'summary.json')),
        commandAdaptation=dict(primary3Filelist=str(filelist),sameModule='CADGeometry',samePackage='nativeexactrelationverification',indexEmission='disabled',moduleCache='dedicated'))
    save('premises.json',premises)
    (OUT/'driver-at-prepare.py').write_bytes(Path(__file__).read_bytes())
    (OUT/'fixture-at-prepare.swift').write_bytes(fixture.read_bytes())
    print(json.dumps(dict(state='PREPARED-NO-EXECUTION',primaryInputs=3,secondaryDeclarations=1648,
        reusedObjects=1648,upperInputs=58,archives=14,checks=len(checks),fixtureSHA256=sha(fixture),
        runnerSHA256=sha(__file__),primaryCommandSHA256=sha(OUT/'primary3-command.json'),
        linkCommandSHA256=sha(OUT/'compile-link-command.json'),inventorySHA256=sha(OUT/'generation-inventory.json'))))
def execute():
    assert not (OUT/'execution-started.json').exists(), 'No blind retry'
    premises=read(OUT/'premises.json');checks=dict(premises['checks'])
    checks[str(OUT/'premises.json')]=sha(OUT/'premises.json')
    products={};runs=[]
    def recheck():
        for mapping in [checks,products]:
            for path,expected in mapping.items():assert sha(path)==expected, 'Changed admitted input: '+path
    recheck();before=head();save('execution-started.json',dict(headBefore=before,premisesSHA256=sha(OUT/'premises.json')))
    (OUT/'driver-at-runtime.py').write_bytes(Path(__file__).read_bytes())
    started_all=time.monotonic();cpu_by_pid={}
    def run(label, command):
        def constrain():
            resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
        log = OUT / (label + '.log')
        started = time.monotonic()
        descendants, peak, stop = set(), 0, None
        cpu_by_pid.clear()
        with log.open('wb') as stream:
            with subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                    start_new_session=True, preexec_fn=constrain) as process:
                def sample():
                    nonlocal peak
                    rows = [row.split() for row in subprocess.check_output(
                        ['ps', '-axo', 'pid=,ppid=,rss=,time='], text=True, timeout=5).splitlines() if row.strip()]
                    owners = {process.pid} | descendants
                    while True:
                        found = {int(pid) for pid, parent, rss, cpu in rows if int(parent) in owners}
                        if found <= owners:
                            break
                        owners |= found
                    descendants.update(owners - {process.pid})
                    peak = max(peak, sum(int(rss) for pid, parent, rss, cpu in rows if int(pid) in owners))
                    for pid, parent, rss, cpu in rows:
                        if int(pid) in owners:
                            seconds = sum(float(value)*60**index for index,value in enumerate(reversed(cpu.split(':'))))
                            cpu_by_pid[int(pid)] = max(cpu_by_pid.get(int(pid), 0), seconds)
                    return {int(pid) for pid, parent, rss, cpu in rows}
                try:
                    while process.poll() is None:
                        sample()
                        if time.monotonic()-started >= 120:
                            stop = 'stage-wall-limit'
                        elif sum(cpu_by_pid.values()) >= 120:
                            stop = 'stage-owned-cpu-limit'
                        if stop:
                            break
                        try:
                            process.wait(timeout=0.25)
                        except subprocess.TimeoutExpired:
                            pass
                finally:
                    survivors = descendants & sample()
                    if stop or survivors or process.poll() is None:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        for pid in survivors:
                            try:
                                os.kill(pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                    process.wait()
                    remaining = descendants & sample()
        record = dict(label=label, command=command, exitCode=process.returncode, boundedStop=stop,
            elapsedSeconds=time.monotonic()-started, cumulativeElapsedSeconds=time.monotonic()-started_all,
            wallLimitSeconds=120, cpuLimitSecondsPerProcess=120, ownedCPULimitSeconds=120,
            sampledOwnedCPUSeconds=sum(cpu_by_pid.values()), peakOwnedProcessResidentSumKiB=peak,
            ownedDescendantsRemaining=sorted(remaining), logSHA256=sha(log))
        runs.append(record)
        checks[str(log)] = record['logSHA256']
        save('runs.json', runs)
        assert not remaining, record
        return process.returncode

    state='primary3-not-started'
    try:
        for label,name,outputs in [
            ('primary3','primary3-command.json',list(premises['freshOutputs'].values())),
            ('archive','archive-command.json',[premises['freshArchive']]),
            ('compile-link','compile-link-command.json',[premises['executable']])]:
            recheck();state=label+'-started'
            if run(label,read(OUT/name))!=0:
                state=label+'-failure';return
            for p in outputs:products[p]=sha(p)
            save(label+'-products.json',dict(checks=checks,products=products,runs=runs))
        recheck();state='runtime-started'
        code=run('runtime',[premises['executable']])
        state='runtime-recorded' if code==0 else 'runtime-failure-recorded'
    finally:
        recheck();events=[];runtime=OUT/'runtime.log'
        if runtime.exists():
            for line in runtime.read_text().splitlines():
                try:
                    value=json.loads(line)
                    if isinstance(value,dict):events.append(value)
                except json.JSONDecodeError:pass
        save('receipt.json',dict(cell=CELL,state=state,cellComplete=False,headBefore=before,headAfter=head(),
            checks=checks,products=products,runs=runs,events=events,postHashesMatch=True,
            ordinaryPublicCalls=sum(e.get('ordinaryCSCalls',0)for e in events),
            productionPrimaryBodies=3,reusedObjects=1648,source6Recompile=0,lowerCodegen=0,moduleEmit=0,
            runtime='OBSERVED' if runtime.exists() else 'UNOBSERVED'))
    print(state)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--execute',action='store_true');args=parser.parse_args()
    if args.execute:execute()
    else:prepare()
