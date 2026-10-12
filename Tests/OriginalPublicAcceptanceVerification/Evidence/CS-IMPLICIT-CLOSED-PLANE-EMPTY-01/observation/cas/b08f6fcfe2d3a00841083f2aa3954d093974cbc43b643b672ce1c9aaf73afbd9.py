#!/usr/bin/env python3
"""Execute one prepared closed implicit ordinary-CS observation after the main-delivery GO."""
import argparse, hashlib, json, os, resource, signal, subprocess, time
from pathlib import Path
ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
OUT = ROOT / '.build/cs-implicit-closed-plane-empty-observation-20261013'
CELL = 'CS-IMPLICIT-CLOSED-PLANE-EMPTY-01'
SOURCE_BASE = 'db25eebec9b323d502faddb38232f26fff84460c'
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def save(name,value): (OUT/name).write_text(json.dumps(value,indent=2)+'\n')
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=5).strip()
def prepare():
    assert not (OUT/'execution-started.json').exists(), 'Observation already started'
    OUT.mkdir(parents=True,exist_ok=True)
    prior=ROOT/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-REVERSE-DYADIC-PARABOLA-ON-HOST-01/acceptance'
    summary=read(prior/'summary.json');manifest=read(prior/'manifest.json')
    part=next(p for p in summary['accepted'] if p['lane']=='native')
    raw=read(ROOT/part['receipt']['path'])['runs'][0]
    command=read(ROOT/part['assemblyCommand']['path'])
    assert command==raw['command'] and raw['exitCode']==0
    archived={}
    for key,value in manifest['files'].items():
        archived[value.get('originalPath',key),value['sha256']]=ROOT/value['path']
    checks={};bindings=[]
    actual_swift={v for v in command if v.endswith('.swift')}
    for name,digest in raw['checks'].items():
        if Path(name).suffix in {'.swift','.py','.json','.log','.txt','.md','.mjs'} and name not in actual_swift:
            saved=archived.get((name,digest))
            if saved is not None:
                checks[str(saved)]=digest
                bindings.append(dict(originalPath=name,sha256=digest,retainedPath=str(saved)))
                continue
        checks[name]=digest
    for name,digest in summary['freshProduction'].items():checks[name]=digest
    for item in [part['receipt'],part['assemblyCommand'],part['sourceModuleReceipt']]:checks[str(ROOT/item['path'])]=item['sha256']
    checks[str(prior/'summary.json')]=sha(prior/'summary.json')
    checks[str(prior/'manifest.json')]=sha(prior/'manifest.json')
    fixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitClosedPlaneEmptyObservation.swift'
    old_fixture=(ROOT/part['compiledFixture']['path']).read_bytes()
    old_proof=Path(next(v for v in command if Path(v).name=='Proof.swift'))
    old_bytes=old_proof.read_bytes();assert old_bytes.endswith(old_fixture)
    proof=OUT/'Proof.swift';proof.write_bytes(old_bytes[:-len(old_fixture)]+fixture.read_bytes())
    source=ROOT/'Tests/CADTopologyCertificationTests/CertifiedImplicitSeamTraversalTests.swift'
    def helper(text):
        start=text.index('    private func closedPlanePcurve()')
        opening=text.index('{',start);depth=0
        for index in range(opening,len(text)):
            depth += (text[index]=='{')-(text[index]=='}')
            if depth==0:return text[start:index+1]
        raise AssertionError('Missing actual constructor body')
    constructor=helper(source.read_text())
    original_assert='        let exact = try #require(try ExactIsoparametricPlanarIntersectionGraph\n            .certified(\n                first: sphere,\n                second: plane,\n                tolerance: tolerance\n            )\n        )'
    adapted_assert='        guard let exact = try ExactIsoparametricPlanarIntersectionGraph\n            .certified(\n                first: sphere,\n                second: plane,\n                tolerance: tolerance\n            ) else { throw ConstructorFailure.missingExactGraph }'
    assert original_assert in constructor
    assert helper(fixture.read_text())==constructor.replace(original_assert,adapted_assert)
    constructor_receipt=ROOT/'Tests/OriginalDomainConsumerVerification/Evidence/M6/receipt.json'
    constructor_premise=read(constructor_receipt);checks[str(constructor_receipt)]=sha(constructor_receipt)
    constructor_sources={}
    for basename in ['AnalyticSurfaceBSplineBuilder','CanonicalAnalyticSurface','ExactIsoparametricPlanarIntersectionGraph']:
        name='Sources/CADGeometry/'+basename+'.swift';path=ROOT/name
        digest=constructor_premise['source_sha256'][name];assert sha(path)==digest
        constructor_sources[str(path)]=digest;checks[str(path)]=digest
    checks[str(source)]=sha(source);checks[str(fixture)]=sha(fixture)
    checks[str(proof)]=sha(proof);checks[str(Path(__file__).resolve())]=sha(__file__)
    command=[str(proof) if v==str(old_proof) else v for v in command]
    command[command.index('-module-cache-path')+1]=str(OUT/'module-cache')
    command[command.index('-module-name')+1]='ImplicitClosedPlaneEmptyObservation'
    command[command.index('-o')+1]=str(OUT/'Observation')
    assert len([v for v in command if v.endswith('.swift')])==58
    assert len([v for v in command if v.endswith('.a')])==14
    save('compile-command.json',command);checks[str(OUT/'compile-command.json')]=sha(OUT/'compile-command.json')
    save('premises.json',dict(cell=CELL,state='prepared-not-executed',runtime='UNOBSERVED',cellComplete=False,
        sourceBase=SOURCE_BASE,checks=checks,historicalBindings=bindings,
        sourceModuleReceipt=part['sourceModuleReceipt'],baselineAssemblyCommand=part['assemblyCommand'],
        cachedImplicitNominalBindings=summary['cachedImplicitNominalBindings'],freshProduction=summary['freshProduction'],
        compiledUpperBodies=56,rebuiltSourceBodies=0,rebuiltLowerBodies=0,
        actualConstructor=dict(path=str(source),helperSHA256=hashlib.sha256(constructor.encode()).hexdigest(),
            adaptedHelperSHA256=hashlib.sha256(helper(fixture.read_text()).encode()).hexdigest(),
            assertionAdaptation=dict(original=original_assert,adapted=adapted_assert),
            cachedSources=constructor_sources,generationReceipt=dict(path=str(constructor_receipt),sha256=sha(constructor_receipt)),
            cellCount=4,freeParameter='firstU',direction='forward',isClosed=True,target='analytic plane Z=2'),
        oracle=dict(closedT=[0,1],targetUV=[[-2,2],[-2,2]],secondHostHomogeneousZ='0',
            weights=['1','5/4','exact binary64 0.8','1'],weightMinimum='exact binary64 0.8 > 0',
            completeTupleImageFiber='empty',authority='Actual rational second host over every original stored cell; no physical sphere or pi identity used.')))
    (OUT/'driver-at-runtime.py').write_bytes(Path(__file__).read_bytes())
    (OUT/'fixture-at-runtime.swift').write_bytes(fixture.read_bytes())
    print(json.dumps(dict(state='PREPARED',compileInputs=58,archives=14,sourceLowerRebuilds=0,
        commandSHA256=sha(OUT/'compile-command.json'),fixtureSHA256=sha(fixture),runnerSHA256=sha(__file__),checks=len(checks))))

def execute():
    assert not (OUT / 'execution-started.json').exists(), 'One observation only; no blind retry.'
    premises = read(OUT / 'premises.json')
    checks = dict(premises['checks'])
    checks[str(OUT / 'premises.json')] = sha(OUT / 'premises.json')
    products, runs = {}, []

    def recheck():
        for mapping in [checks, products]:
            for path, expected in mapping.items():
                assert sha(path) == expected, 'Changed admitted observation input: ' + path

    recheck()
    before = head()
    save('execution-started.json', dict(headBefore=before, premisesSHA256=checks[str(OUT/'premises.json')]))
    started_all = time.monotonic()
    cpu_by_pid = {}

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

    state = 'compile-not-started'
    try:
        command = read(OUT/'compile-command.json')
        state = 'compile-started'
        if run('compile-link', command) != 0:
            state = 'compile-failure'
            return
        product = OUT / 'Observation'
        products[str(product)] = sha(product)
        recheck()
        state = 'runtime-started'
        code = run('runtime', [str(product)])
        state = 'runtime-recorded' if code == 0 else 'runtime-failure-recorded'
    finally:
        recheck()
        events = []
        runtime = OUT/'runtime.log'
        if runtime.exists():
            for line in runtime.read_text().splitlines():
                try:
                    value = json.loads(line)
                    if isinstance(value, dict):
                        events.append(value)
                except json.JSONDecodeError:
                    pass
        save('receipt.json', dict(cell=CELL, state=state, cellComplete=False,
            headBefore=before, headAfter=head(), sourceBase=SOURCE_BASE,
            checks=checks, products=products, runs=runs, events=events,
            ordinaryPublicCalls=sum(event.get('ordinaryCSCalls',0) for event in events),
            rebuiltSourceBodies=0, rebuiltLowerBodies=0, newProductionBodies=0, compiledUpperBodies=56,
            postHashesMatch=True, runtime='OBSERVED' if runtime.exists() else 'UNOBSERVED'))
    print(state)


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--execute',action='store_true')
    options=parser.parse_args()
    if options.execute: execute()
    else: prepare()
