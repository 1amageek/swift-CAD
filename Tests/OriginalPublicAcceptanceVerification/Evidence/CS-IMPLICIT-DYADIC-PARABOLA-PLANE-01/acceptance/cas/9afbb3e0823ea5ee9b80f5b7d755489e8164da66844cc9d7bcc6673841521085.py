#!/usr/bin/env python3
"""Prepare, then explicitly execute one bounded original implicit ordinary-CS observation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
CELL = 'CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01'
ACCEPTANCE = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/acceptance'
SUMMARY_SHA = 'bec8cfd5451bfd3ffc4b79b8eecf5ffdd098d792fc34590028a110fe29999fca'
RAW_SHA = 'ee5ee7fe006e9a923c9c9fe7382d1e64ae51faf882de54134bdbcea3bb63691c'
M6_SHA = '470c698fb6d497c2c8a9f4a7aa96352244418b49064bd42815dfbcab181c0dfd'
SOURCE_BASE = 'd59d791bbcb669001cf61144a33745323f29e6dd'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


def head():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True, timeout=5).strip()


def prepare():
    assert OUT.is_relative_to(ROOT / '.build')
    assert not (OUT / 'premises.json').exists(), 'Preparation is immutable; use the prepared execution mode.'
    checks = {}

    def admit(path, expected):
        path = Path(path)
        assert path.is_file() and sha(path) == expected, 'Receipt premise differs: ' + str(path)
        checks[str(path)] = expected

    summary_path = ACCEPTANCE / 'summary.json'
    admit(summary_path, SUMMARY_SHA)
    summary = read(summary_path)
    accepted = next(row for row in summary['accepted'] if row['lane'] == 'native')
    raw_path = ROOT / accepted['receipt']['path']
    admit(raw_path, RAW_SHA)
    raw = read(raw_path)
    assert raw['success'] and raw['lane'] == 'native'
    excluded = {}
    unused = {str(ROOT / 'Tests/OriginalPublicAcceptanceVerification' / name) for name in
              ['CertifiedSphereConeApexEmptyAcceptance.py', 'CertifiedSphereConeApexEmptyAcceptance.swift']}
    for path, expected in raw['checks'].items():
        if path in unused:
            excluded[path] = dict(recordedSHA256=expected,
                reason='Historical cert fixture/runner not compiled or invoked; exact archived copies remain admitted.')
        else:
            admit(path, expected)
    for path, expected in raw['products'].items():
        admit(path, expected)
    for path, expected in raw['freshProduction'].items():
        admit(path, expected)
    for descriptor in [accepted['assemblyCommand'], accepted['sourceModuleReceipt']]:
        admit(ROOT / descriptor['path'], descriptor['sha256'])
    command = read(ROOT / accepted['assemblyCommand']['path'])
    assert command == next(row['command'] for row in raw['runs'] if row['label'] == 'compile-link')
    m6_path = ROOT / 'Tests/OriginalDomainConsumerVerification/Evidence/M6/receipt.json'
    admit(m6_path, M6_SHA)
    cached = read(m6_path)['source_sha256']
    names = ['CertifiedImplicitIntersectionCurve.swift', 'CertifiedImplicitIntersectionGraphCell.swift',
             'DefaultCertifiedImplicitCurveAnalyticSurfaceIntersector.swift', 'ImplicitCurveIntervalJetEncloser.swift',
             'CertifiedImplicitCurveAnalyticSurfaceIntersecting.swift', 'SurfaceIntersectionParameterBox.swift',
             'SurfaceIntersectionParameterPair.swift', 'Curve3D.swift', 'ExactAffineBSplineSurfacePatch.swift']
    selected_cached = {}
    for name in names:
        path = ROOT / 'Sources/CADGeometry' / name
        expected = cached[str(path.relative_to(ROOT))]
        admit(path, expected)
        selected_cached[str(path)] = expected
    fixture = OUT / 'Observation.swift'
    test = ROOT / 'Tests/CADGeometryTests/CertifiedImplicitIntersectionCurveTests.swift'
    text = test.read_text()
    start = text.index('  private func dyadicPlaneParabolaCurve(')
    end = text.index('\n  @Test func implicitLiftBounds', start)
    helper = text[start:end].rstrip()
    assert helper in fixture.read_text(), 'Actual constructor expression bytes changed.'
    for path in [test, fixture, Path(__file__), OUT / 'constructor-helper.swift.txt']:
        admit(path, sha(path))
    upper = [Path(value) for value in command if value.endswith('.swift') and '/upper/' in value]
    assert len(upper) == 41
    excluded_bodies = {'DefaultSurfaceSurfaceIntersector.swift', 'PlanePlaneSurfaceIntersector.swift'}
    replacement = {}
    upper_dir = OUT / 'upper'
    upper_dir.mkdir()
    for source in upper:
        if source.name not in excluded_bodies:
            target = upper_dir / source.name
            target.write_bytes(source.read_bytes())
            admit(target, raw['checks'][str(source)])
            replacement[str(source)] = str(target)
    assert len(replacement) == 39
    original_proof = Path(next(value for value in command if value.endswith('/Proof.swift')))
    historical_fixture = original_proof.parent / 'CertifiedSphereConeApexEmptyAcceptance.swift'
    assert original_proof.read_bytes().endswith(historical_fixture.read_bytes())
    prefix = original_proof.read_bytes()[:-len(historical_fixture.read_bytes())]
    proof = OUT / 'Proof.swift'
    proof.write_bytes(prefix + fixture.read_bytes())
    admit(proof, sha(proof))
    assembled = []
    for value in command:
        if value in replacement:
            assembled.append(replacement[value])
        elif value in {str(path) for path in upper if path.name in excluded_bodies}:
            continue
        elif value == str(original_proof):
            assembled.append(str(proof))
        else:
            assembled.append(value)
    assembled[assembled.index('-module-name') + 1] = 'ImplicitDyadicParabolaObservation'
    assembled[assembled.index('-module-cache-path') + 1] = str(OUT / 'module-cache')
    assembled[assembled.index('-o') + 1] = str(OUT / 'Observation')
    assert len([value for value in assembled if value.endswith('.swift')]) == 41
    assert len([value for value in assembled if value.endswith('.a')]) == 13
    assert '-DNATIVE_DOMAIN_ISOLATED_VERIFICATION' not in assembled
    save('compile-command.json', assembled)
    admit(OUT / 'compile-command.json', sha(OUT / 'compile-command.json'))
    metadata = dict(cell=CELL, state='prepared-not-executed', runtime='UNOBSERVED', cellComplete=False,
        sourceBase=SOURCE_BASE, headAtPreparation=head(), checks=checks,
        currentProduction=raw['freshProduction'], selectedCachedSources=selected_cached,
        excludedUnusedHistoricalFixtureChecks=excluded,
        constructorHelper=dict(path=str(test), firstLine=588, lastLine=619,
            exactExpressionSHA256=hashlib.sha256(helper.encode()).hexdigest()),
        parentReceipt=str(raw_path), parentSHA256=RAW_SHA,
        sourceReceipt=accepted['sourceModuleReceipt'], upperBodies=39, swiftInputs=41, archives=13,
        rebuiltSourceBodies=0, rebuiltLowerBodies=0, newProductionBodies=0,
        oracle=dict(tuple=['1/2','1/4','1/2'], hostUV=[['1/4','1/2'],['1/2','1/2']],
            xyz=['1/128','1/128','0'], dimensions=[0,0,0], incidents=[1,1,1,1]),
        limits=dict(wallSeconds=120, CPUSecondsPerProcess=120, cumulativeOwnedCPUSeconds=120),
        executionCommand=['python3', str(Path(__file__).resolve()), '--execute'])
    save('premises.json', metadata)
    print(json.dumps(dict(state=metadata['state'], checks=len(checks), runtime='UNOBSERVED')))


def execute():
    assert not (OUT / 'execution-started.json').exists(), 'One observation only; no blind retry.'
    premises = read(OUT / 'premises.json')
    checks = premises['checks']
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
                        if time.monotonic()-started_all >= 120:
                            stop = 'cumulative-wall-limit'
                        elif sum(cpu_by_pid.values()) >= 120:
                            stop = 'cumulative-owned-cpu-limit'
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
            wallLimitSeconds=120, cpuLimitSecondsPerProcess=120, cumulativeOwnedCPULimitSeconds=120,
            sampledCumulativeCPUSeconds=sum(cpu_by_pid.values()), peakOwnedProcessResidentSumKiB=peak,
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
        if time.monotonic()-started_all >= 120 or sum(cpu_by_pid.values()) >= 120:
            state = 'runtime-not-started-resource-bound'
            return
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
            rebuiltSourceBodies=0, rebuiltLowerBodies=0, newProductionBodies=0,
            postHashesMatch=True, runtime='OBSERVED' if runtime.exists() else 'UNOBSERVED'))
    print(state)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute', action='store_true')
    options = parser.parse_args()
    if options.execute:
        execute()
    else:
        prepare()
