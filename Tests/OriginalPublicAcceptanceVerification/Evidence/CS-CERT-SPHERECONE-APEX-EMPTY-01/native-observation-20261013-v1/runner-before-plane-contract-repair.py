#!/usr/bin/env python3
"""Observe one actual apex constructor and one rich CS call over admitted current Native bodies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--artifacts', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    out, artifacts = args.output.resolve(), args.artifacts.resolve()
    assert out.is_relative_to(root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01')
    assert artifacts.is_relative_to(root / '.build')
    out.mkdir(parents=True, exist_ok=False)
    artifacts.mkdir(parents=True, exist_ok=False)
    checks, current, products, runs, events = {}, {}, {}, [], []

    def save(name, value):
        (out / name).write_text(json.dumps(value, indent=2) + '\n')

    def admit(path, expected):
        path = Path(path)
        if not path.is_file() or sha(path) != expected:
            raise RuntimeError('Receipt premise differs: ' + str(path))
        checks[str(path)] = expected

    def recheck():
        for mapping in [checks, current, products]:
            for path, expected in mapping.items():
                if sha(path) != expected:
                    raise RuntimeError('Changed observation input: ' + path)

    def head():
        return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True, timeout=5).strip()

    before = head()
    observation_base = 'b70e781f55b62eda77b62cfa270f016939017f5f'
    control_delta = subprocess.check_output(['git', 'diff', '--name-only', observation_base, before],
        cwd=root, text=True, timeout=5).splitlines()
    assert set(control_delta) <= {'PROGRESS.md', 'Sources/CADGeometry/OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md'}
    parent_path = root / '.build/cs-angular-physical-acceptance-native-20261012-v10/receipt.json'
    admit(parent_path, '50c6bbdfd196b7266930cf6acee69eeedec153e173f0c3a263faece881d673d9')
    parent = read(parent_path)
    assert parent['success'] and parent['lane'] == 'native'
    for path, expected in parent['checks'].items():
        admit(path, expected)
    for path, expected in parent['products'].items():
        admit(path, expected)
    for path, expected in parent['freshProduction'].items():
        admit(path, expected)
        current[path] = expected
    cache_path = root / 'Tests/OriginalDomainConsumerVerification/Evidence/M6/receipt.json'
    admit(cache_path, '470c698fb6d497c2c8a9f4a7aa96352244418b49064bd42815dfbcab181c0dfd')
    cached = read(cache_path)['source_sha256']
    selected = {}
    names = ['DefaultCertifiedIntersectionReductionResolver.swift', 'DefaultCertifiedIntersectionReductionIntersector.swift',
        'DefaultCertifiedIntersectionCandidateVerifier.swift', 'DefaultCertifiedIntersectionSpatialDisjointnessResolver.swift',
        'CertifiedSphereConeIntersectionCurve.swift', 'SphereConeApexContactIntersector.swift',
        'GeneralSphereConeSurfaceIntersector.swift', 'CertifiedAnalyticAnalyticIntersectionCurve.swift',
        'AnalyticSurface3D.swift', 'AnalyticBasis.swift', 'Surface3D.swift', 'CertifiedIntersectionCurve3D.swift',
        'SurfaceIntersectionSplineBuilder.swift', 'PlaneSphereSurfaceIntersector.swift']
    for name in names:
        matches = list((root / 'Sources/CADGeometry').rglob(name))
        assert len(matches) == 1
        path = matches[0]
        expected = cached[str(path.relative_to(root))]
        admit(path, expected)
        current[str(path)] = expected
        selected[str(path)] = expected
    fixture = Path(__file__).with_suffix('.swift')
    constructor_test = root / 'Tests/CADGeometryTests/CertifiedSphereConeSpatialDifferentialBoundsTests.swift'
    facade_source = root / 'Sources/CADGeometry/DefaultSurfaceSurfaceIntersector.swift'
    for path in [fixture, Path(__file__), constructor_test, facade_source]:
        admit(path, sha(path))
    current[str(facade_source)] = sha(facade_source)
    admit(facade_source, 'ae19ffed50abe1e1f08ce27f4d2ba8dc5b92e9c0858f60e39aa951af9c19321b')
    oracle_dir = root / '.build/cert-spherecone-apex-height-semantic-robustness-20261012'
    oracle_expected = {'worksheet.json': 'a18d0488a08e53eaa7b1419709067109bcfa5d66cbf8e61263077b37f23ea09e',
        'worksheet.py': 'de52865e435bdbbc0293c258d16c311a25cdbabf78ce7955157753434d5c1d13',
        'calculation.log': '331df2b19aa5fc6c973d39c5a8859ca9edd773f2dbc233b748d462df7340317f',
        'metadata.json': 'a7ee6942ab7f174bf7e437a0f9dc7274680e5af7d5f8f053513a7c9bbfc7a085'}
    for name, expected in oracle_expected.items():
        admit(oracle_dir / name, expected)
        (out / ('oracle-' + name)).write_bytes((oracle_dir / name).read_bytes())
        admit(out / ('oracle-' + name), expected)
    command_path = parent_path.parent / 'compile-command.json'
    admit(command_path, sha(command_path))
    old = read(command_path)
    assert old == next(run['command'] for run in parent['runs'] if run['label'] == 'compile-link')
    old_proof = Path(next(path for path in old if path.endswith('/Proof.swift')))
    old_fixture = root / 'Tests/OriginalPublicAcceptanceVerification/AngularPhysicalArcPlaneAcceptance.swift'
    proof_text = old_proof.read_text()
    assert proof_text.endswith(old_fixture.read_text())
    prefix = proof_text[:-len(old_fixture.read_text())]
    proof = artifacts / 'Proof.swift'
    proof.write_text(prefix + fixture.read_text())
    facade = artifacts / facade_source.name
    facade.write_text('import CADCore\n@testable import CADGeometry\n@testable import PublicLiftPlane\n'
        'import enum PublicLiftPlane.GeometryExactScalarFailure\n' + facade_source.read_text())
    for path in [proof, facade]:
        admit(path, sha(path))
    product = artifacts / 'Observation'
    command = []
    for value in old:
        if value == str(old_proof):
            command.extend([str(facade), str(proof)])
        else:
            command.append(value)
    command[command.index('-module-name')+1] = 'CertifiedSphereConeApexEmptyObservation'
    command[command.index('-module-cache-path')+1] = str(artifacts / 'module-cache')
    command[command.index('-o')+1] = str(product)
    assert len([path for path in command if path.endswith('.swift')]) == 39
    save('compile-command.json', command)
    premises = dict(cell='CS-CERT-SPHERECONE-APEX-EMPTY-01', headBefore=before,
        observationBase=observation_base, controlOnlyDelta=control_delta,
        sourceCommit='6b8ea4954b616f9669eed1536bd02baa5021a79f', parentReceipt=str(parent_path),
        parentSHA256=sha(parent_path), checks=checks, currentSource=current,
        unchangedSelectedCachedSources=selected, freshUpperBodies=37, sourcePhaseRebuilds=0,
        lowerRebuilds=0, compilerSwiftInputs=39, archiveCount=12, ordinaryRichCSCalls=1,
        oracle='abs(Z) < 15/16 < 1 < 2 for both mathematical and imported binary coefficients; all material sets empty.')
    save('premises-before.json', premises)

    def execute(label, arguments):
        def constrain():
            resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
        started = time.monotonic()
        descendants, peak, cpu_by_pid = set(), 0, {}
        bounded_stop = None
        log = out / (label + '.log')
        with log.open('wb') as stream:
            process = subprocess.Popen(arguments, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=constrain)

            def sample():
                nonlocal peak
                rows = [line.split() for line in subprocess.check_output(
                    ['ps', '-axo', 'pid=,ppid=,rss=,time='], text=True, timeout=5).splitlines() if line.strip()]
                owners = {process.pid} | descendants
                while True:
                    found = {int(pid) for pid, parent, rss, cpu in rows if int(parent) in owners}
                    if found <= owners:
                        break
                    owners |= found
                descendants.update(owners - {process.pid})
                live = {int(pid) for pid, parent, rss, cpu in rows}
                peak = max(peak, sum(int(rss) for pid, parent, rss, cpu in rows if int(pid) in owners))
                for pid, parent, rss, cpu in rows:
                    if int(pid) in owners:
                        seconds = sum(float(value)*60**index for index, value in enumerate(reversed(cpu.split(':'))))
                        cpu_by_pid[int(pid)] = max(cpu_by_pid.get(int(pid), 0), seconds)
                return live, owners & live

            try:
                while process.poll() is None:
                    live, owned = sample()
                    if time.monotonic()-started >= 120:
                        bounded_stop = 'wall-limit'
                    elif sum(cpu_by_pid.values()) >= 120:
                        bounded_stop = 'sampled-owned-cpu-limit'
                    elif len(owned) > 8:
                        bounded_stop = 'owned-process-limit'
                    if bounded_stop:
                        break
                    try:
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
            finally:
                live, owned = sample()
                survivors = descendants & live
                if bounded_stop or survivors:
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
                live, owned = sample()
                remaining = descendants & live
        record = dict(label=label, command=arguments, exitCode=process.returncode,
            elapsedSeconds=time.monotonic()-started, wallLimitSeconds=120,
            cpuLimitSecondsPerProcess=120, sampledOwnedCPULimitSeconds=120, ownedProcessLimit=8,
            sampledCPUSeconds=sum(cpu_by_pid.values()), peakOwnedProcessResidentSumKiB=peak,
            ownedDescendantsRemaining=sorted(remaining), boundedStop=bounded_stop, logSHA256=sha(log))
        runs.append(record)
        admit(log, record['logSHA256'])
        save('runs.json', runs)
        print(label, process.returncode, round(record['elapsedSeconds'],3), flush=True)
        assert not remaining
        return process.returncode

    state = 'assembly-prepared'
    try:
        recheck()
        compiled = execute('compile-link', command)
        state = 'compile-failure'
        if compiled == 0:
            products[str(product)] = sha(product)
            recheck()
            execute('runtime-once', [str(product)])
            for line in (out / 'runtime-once.log').read_text().splitlines():
                if line.startswith('{'):
                    events.append(json.loads(line))
            save('observation.json', events)
            state = events[-1]['stage'] if events else 'missing-observation'
    finally:
        recheck()
        after = head()
        save('receipt.json', dict(cell='CS-CERT-SPHERECONE-APEX-EMPTY-01', state=state,
            cellComplete=False, observationBase=observation_base, headBefore=before, headAfter=after,
            parentReceipt=str(parent_path), parentSHA256=sha(parent_path), checks=checks,
            currentSource=current, unchangedSelectedCachedSources=selected,
            postHashesMatch=True, products=products, runs=runs, events=events,
            ordinaryPublicCalls=sum(event.get('stage') == 'before-public-entry' for event in events),
            sourcePhaseRebuilds=0, lowerRebuilds=0, freshUpperBodies=37, compilerSwiftInputs=39,
            scope='One actual original SSI constructor and one ordinary rich CS call; numerical empty alone is not source/domain exclusion acceptance.'))
    print('OBSERVATION', state, flush=True)


if __name__ == '__main__':
    main()
