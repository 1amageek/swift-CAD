#!/usr/bin/env python3
"""Execute one prepared split implicit ordinary-CS observation after the main-delivery GO."""
import argparse, hashlib, json, os, resource, signal, subprocess, time
from pathlib import Path
ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
OUT = Path(__file__).resolve().parent
CELL = 'CS-IMPLICIT-SPLIT-DYADIC-PARABOLA-PLANE-01'
SOURCE_BASE = 'e9905c0b'
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def save(name,value): (OUT/name).write_text(json.dumps(value,indent=2)+'\n')
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=5).strip()
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
    parser=argparse.ArgumentParser()
    parser.add_argument('--execute',action='store_true')
    options=parser.parse_args()
    if options.execute: execute()
    else: print('PREPARED; compile/runtime UNOBSERVED. Await main-delivery GO.')
