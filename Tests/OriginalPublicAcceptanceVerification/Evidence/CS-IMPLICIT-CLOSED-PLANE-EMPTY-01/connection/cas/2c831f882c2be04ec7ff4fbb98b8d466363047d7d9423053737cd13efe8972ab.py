#!/usr/bin/env python3
"""Prepare or execute the generation-bound closed constructor controls and one ordinary CS query."""
import argparse, hashlib, json, os, resource, signal, subprocess, time, shlex
from pathlib import Path
ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
OUT = ROOT / '.build/cs-implicit-closed-connection-native-20261013-v1'
CELL = 'CS-IMPLICIT-CLOSED-PLANE-EMPTY-01'
SOURCE_BASE = 'db25eebec9b323d502faddb38232f26fff84460c'
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def save(name,value): (OUT/name).write_text(json.dumps(value,indent=2)+'\n')
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=5).strip()
def prepare():
    assert not (OUT/'execution-started.json').exists(), 'Dedicated observation already started'
    OUT.mkdir(parents=True,exist_ok=True)
    prior=ROOT/'Tests/OriginalPublicAcceptanceVerification/Evidence'/CELL/'observation'
    baseline=read(prior/'receipt.json'); manifest=read(prior/'manifest.json')
    assert baseline['ordinaryPublicCalls']==0 and [run['exitCode'] for run in baseline['runs']]==[0,2]
    oldcommand=read(prior/'compile-command.json')
    archived={(v.get('originalPath',k),v['sha256']):ROOT/v['path'] for k,v in manifest['files'].items()}
    checks={};historical=[]
    for name,digest in baseline['checks'].items():
        retained=archived.get((name,digest))
        if retained is not None and Path(name).suffix in {'.swift','.py','.json','.log','.txt','.md','.mjs'}:
            assert sha(retained)==digest;checks[str(retained)]=digest
            historical.append(dict(originalPath=name,sha256=digest,retainedPath=str(retained)))
        else:
            assert sha(name)==digest;checks[name]=digest
    for name in ['receipt.json','manifest.json','summary.json','bindings.json','compile-command.json']:
        checks[str(prior/name)]=sha(prior/name)
    generation=ROOT/'Tests/OriginalDomainConsumerVerification/Evidence/M6/receipt.json'
    m6=read(generation);checks[str(generation)]=sha(generation)
    cache=Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-native-production')
    objects=cache/'out/Intermediates.noindex/NativeExactRelationVerification.build/Debug/CADGeometry-t.build/Objects-normal/arm64'
    filelist=objects/'CADGeometry.SwiftFileList';linklist=objects/'CADGeometry.LinkFileList'
    original_sources=filelist.read_text().splitlines();original_objects=linklist.read_text().splitlines()
    expected_sources={p:h for p,h in m6['compiler_inputs'].items() if '/Sources/CADGeometry/' in p and p.endswith('.swift')}
    assert len(original_sources)==1651 and set(original_sources)==set(expected_sources)
    assert len(original_objects)==1651 and len(set(original_objects))==1651
    selected={
      'CertifiedImplicitIntersectionGraphCell.swift':'3bfd2a0d38da969f7b4b347199c9c35be5f97a5e0ced918ca1353491cf9d18fa',
      'ExactIsoparametricPlanarIntersectionGraph.swift':'abfb0fcb4bff4ad2c1f1a292101373aae8fbb325bb7b7cc5a0f4847e34636c24'}
    fresh_sources={}; fresh_outputs={};bindings=[]
    (OUT/'selected').mkdir(exist_ok=True)
    for name,digest in selected.items():
        current=ROOT/'Sources/CADGeometry'/name;assert sha(current)==digest
        snapshot=OUT/'selected'/name;snapshot.write_bytes(current.read_bytes())
        checks[str(current)]=digest;checks[str(snapshot)]=digest
        fresh_sources[name]=str(snapshot);fresh_outputs[name]=str(OUT/(Path(name).stem+'.o'))
    selected_sources=[]
    generation_repo=Path('/private/tmp/cad-di-m6-consumers-20261009')
    generation_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=generation_repo,text=True,timeout=5).strip()
    recovered=[]
    for name in original_sources:
        digest=expected_sources[name];observed=sha(name);retained=name;retrieval='current-generation-bytes-match'
        if observed!=digest:
            relative=str(Path(name).relative_to(generation_repo))
            data=subprocess.check_output(['git','show',generation_commit+':'+relative],cwd=generation_repo,timeout=5)
            assert hashlib.sha256(data).hexdigest()==digest, 'Unavailable generation source: '+name
            snapshot=OUT/'recovered-generation'/relative;snapshot.parent.mkdir(parents=True,exist_ok=True);snapshot.write_bytes(data)
            retained=str(snapshot);retrieval='git-exact-generation-source'
            recovered.append(dict(originalPath=name,observedSHA256=observed,generationSHA256=digest,
                retainedPath=retained,repository=str(generation_repo),commit=generation_commit,gitPath=relative))
        checks[retained]=digest
        chosen=fresh_sources.get(Path(name).name,retained);selected_sources.append(chosen)
        bindings.append(dict(generationInput=name,generationSHA256=digest,retainedGenerationInput=retained,
            retrieval=retrieval,observedOriginalSHA256=observed,compiledInput=chosen,
            compiledSHA256=checks[chosen],primary=Path(name).name in selected))
    archive_inputs=[];object_bindings=[]
    for name in original_objects:
        key=str(Path(name).relative_to(cache));digest=m6['products'][key]
        assert sha(name)==digest;checks[name]=digest
        basename=Path(name).stem+'.swift';chosen=fresh_outputs.get(basename,name)
        archive_inputs.append(chosen);object_bindings.append(dict(generationObject=name,generationProductKey=key,
            generationSHA256=digest,archiveInput=chosen,replaced=chosen!=name))
    assert sum(v['primary'] for v in bindings)==2 and sum(v['replaced'] for v in object_bindings)==2
    selected_filelist=OUT/'generation-filelist-with-selected2.txt'
    selected_filelist.write_text(''.join(p+'\n' for p in selected_sources))
    checks[str(selected_filelist)]=sha(selected_filelist)
    log=ROOT/'Tests/OriginalDomainConsumerVerification/Evidence/M6/diagnostic-build.log'
    raw_job=next(shlex.split(line) for line in log.read_text().splitlines()
        if 'swift-frontend -frontend -c -filelist' in line)
    checks[str(log)]=sha(log)
    save('generation-neighbor-batch-command.json',raw_job)
    job=[];i=0
    removed=[]
    remove_pairs={'-primary-file','-o','-supplementary-output-file-map','-index-unit-output-path','-index-store-path'}
    while i<len(raw_job):
        value=raw_job[i]
        if value in remove_pairs:
            removed.append(raw_job[i:i+2]);i+=2;continue
        if value=='-filelist':job.extend([value,str(selected_filelist)]);i+=2;continue
        if value=='-module-cache-path':job.extend([value,str(OUT/'primary-module-cache')]);i+=2;continue
        job.append(value);i+=1
    assert job[job.index('-module-name')+1]=='CADGeometry'
    assert job[job.index('-package-name')+1]=='nativeexactrelationverification'
    for value in fresh_sources.values():job.extend(['-primary-file',value])
    for value in fresh_outputs.values():job.extend(['-o',value])
    assert job.count('-primary-file')==2 and job.count('-o')==2
    for flag in ['-explicit-swift-module-map-file','-const-gather-protocols-file','-debug-module-path']:
        path=job[job.index(flag)+1];checks[path]=sha(path)
    checks[job[0]]=sha(job[0])
    save('primary2-command.json',job)
    archive=OUT/'libCachedCADGeometryConnection.a'
    archive_command=['ar','-rcs',str(archive),*archive_inputs]
    save('archive-command.json',archive_command)
    fixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitClosedPlaneEmptyConnectionAcceptance.swift'
    old_fixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitClosedPlaneEmptyObservation.swift'
    old_proof=Path(next(v for v in oldcommand if Path(v).name=='Proof.swift'))
    old_bytes=old_proof.read_bytes();assert old_bytes.endswith(old_fixture.read_bytes())
    proof=OUT/'Proof.swift';proof.write_bytes(old_bytes[:-len(old_fixture.read_bytes())]+fixture.read_bytes())
    command=oldcommand.copy();command[command.index(str(old_proof))]=str(proof)
    old_archive=next(v for v in command if v.endswith('/libCachedCADGeometry.a'))
    command[command.index(old_archive)]=str(archive)
    command[command.index('-module-cache-path')+1]=str(OUT/'upper-module-cache')
    command[command.index('-module-name')+1]='ImplicitClosedPlaneEmptyConnectionAcceptance'
    command[command.index('-o')+1]=str(OUT/'ConnectionObservation')
    assert len([v for v in command if v.endswith('.swift')])==58
    assert len([v for v in command if v.endswith('.a')])==14
    save('compile-link-command.json',command)
    for p in [fixture,proof,Path(__file__).resolve(),filelist,linklist]:checks[str(p)]=sha(p)
    for n in ['primary2-command.json','archive-command.json','compile-link-command.json','generation-neighbor-batch-command.json']:
        checks[str(OUT/n)]=sha(OUT/n)
    save('generation-inventory.json',dict(generationReceipt=dict(path=str(generation),sha256=sha(generation)),
        metadataAuthority='Current filelist/linklist are inventory carriers, not claimed historically hashed. Full source set equals M6.compiler_inputs CADGeometry set; each original source and each object matches its M6 generation SHA.',
        sourceBindings=bindings,objectBindings=object_bindings,recoveredGenerationSources=recovered))
    checks[str(OUT/'generation-inventory.json')]=sha(OUT/'generation-inventory.json')
    save('premises.json',dict(cell=CELL,state='prepared-pending-root-execution-GO',checks=checks,
        originalObservation=dict(path=str(prior/'summary.json'),sha256=sha(prior/'summary.json')),
        historicalBindings=historical,selectedSources=selected,freshOutputs=fresh_outputs,
        freshArchive=str(archive),executable=str(OUT/'ConnectionObservation'),
        productionPrimaryBodies=2,generationDeclarationInputs=1651,reusedObjectBodies=1649,
        moduleEmit=0,source6Recompile=0,lowerCodegen=0,upperBodies=56,ordinaryCallsPlanned=1,
        moduleAuthority='Cached CADGeometry module retained: public layout/signatures/conformances unchanged, no inlinable body change; new internal predicate is called only by the two fresh same-module primaries.',
        commandAdaptation=dict(removed=removed,primary2Filelist=str(selected_filelist),sameModule='CADGeometry',samePackage='nativeexactrelationverification',indexEmission='disabled',moduleCache='dedicated'),
        controls=['actual original4cells closed constructor','all4cells reversed order/direction constructor','swapped Native hosts with exact role/UV permutation constructor','upper firstV nextDown and all3 anchors shifted must not yield a successful closed constructor'],
        oracle=dict(wholeT=[0,1],targetUV=[[-2,2],[-2,2]],tupleImageFiber='empty',source='actual second Native host homogeneousZ0/strictlypositive exactbinary64 weights'),
        guards=dict(wallSecondsPerStage=120,perProcessCPUSeconds=120,ownedCPUSecondsPerStage=120,publicCaps='unchanged defaults')))
    (OUT/'driver-at-prepare.py').write_bytes(Path(__file__).read_bytes())
    (OUT/'fixture-at-prepare.swift').write_bytes(fixture.read_bytes())
    print(json.dumps(dict(state='PREPARED-NO-EXECUTION',primaryInputs=2,secondaryDeclarations=1649,
        reusedObjects=1649,upperInputs=58,archives=14,checks=len(checks),recoveredGenerationSources=len(recovered),fixtureSHA256=sha(fixture),runnerSHA256=sha(__file__),
        primaryCommandSHA256=sha(OUT/'primary2-command.json'),linkCommandSHA256=sha(OUT/'compile-link-command.json'),
        inventorySHA256=sha(OUT/'generation-inventory.json'))))
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

    state='primary2-not-started'
    try:
        for label,name,outputs in [
            ('primary2','primary2-command.json',list(premises['freshOutputs'].values())),
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
            productionPrimaryBodies=2,reusedObjects=1649,source6Recompile=0,lowerCodegen=0,moduleEmit=0,
            runtime='OBSERVED' if runtime.exists() else 'UNOBSERVED'))
    print(state)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--execute',action='store_true');args=parser.parse_args()
    if args.execute:execute()
    else:prepare()
