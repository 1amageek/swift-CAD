#!/usr/bin/env python3
"""Observe one fixed rational pcurve through the admitted actual Native public path."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--timeout', type=int, default=120)
args = parser.parse_args()
assert 0 < args.timeout <= 120
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
prior_dir = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-COLLAPSED-CLOSED-01/accepted/native'
prior_path = prior_dir / 'receipt.json'
expected_prior = '2fb5a30d5cd3b4cdc3e64b01071a018300ed7425df139985e4239ed3c78d428c'
checks, products, runs = {}, {}, []


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')


def admit(path, expected):
    path = Path(path)
    assert sha(path) == expected, str(path)
    checks[str(path)] = expected


def recheck():
    for name, expected in checks.items():
        assert sha(name) == expected, name
    for name, expected in products.items():
        assert sha(name) == expected, name


admit(prior_path, expected_prior)
prior = json.loads(prior_path.read_text())
assert prior['lane'] == 'native' and prior['state'] == 'complete-collapsed-boundary-cell-verified'
for group in ['checks', 'freshProduction', 'products']:
    for name, expected in prior[group].items():
        admit(name, expected)
for run in prior['runs']:
    assert run['exitCode'] == 0 and not run['timedOut']
    admit(prior_dir / (run['label'] + '.log'), run['logSHA256'])
link = list(next(run['command'] for run in prior['runs'] if run['label'] == 'compile-link-cell'))
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/RationalQuadraticBoundaryObservation.swift'
old_fixture = root / 'Tests/OriginalPublicAcceptanceVerification/NativeCollapsedBoundaryAcceptance.swift'
assert link.count(str(old_fixture)) == 1
link[link.index(str(old_fixture))] = str(fixture)
proof = out / 'RationalQuadraticBoundaryProof'
link[link.index('-o') + 1] = str(proof)
admit(fixture, sha(fixture))
admit(Path(__file__).resolve(), sha(__file__))
for path, name in [(fixture, 'Fixture.swift'), (Path(__file__).resolve(), 'driver.py')]:
    shutil.copyfile(path, out / name)
    admit(out / name, sha(path))
(out / '.gitignore').write_text('/RationalQuadraticBoundaryProof\n')
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
assert head == '0422fa0c6151467da32b5fdf7e00bccbc4f5d64f'
save('frozen-input.json', dict(cell='B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01', head=head,
    curve=dict(degree=1, knots=[0,0,1,1], controls=[[0,'7/32',0],[1,'7/32',0]]),
    surface=dict(degrees=[1,1], knots=[[0,0,1,1],[0,0,1,1]], controls=[[[0,0,0],[1,0,0]],[[0,1,0],[1,1,0]]]),
    request='Full original closed T,U,V=[0,1]; closed material selection',
    face=dict(validation='exact', role='outer', orientations=['forward']*3,
        pcurves=['constantV(0,0,1/2)','constantU(1/2,0,1/4)',
            dict(degree=2,knots=[0,0,0,1,1,1],controls=[['1/2','1/4'],['1/4','1/4'],[0,0]],weights=[1,3,1])]),
    oracle=dict(denominator='D(s)=1+4s-4s^2>=1 on [0,1]',
        pcurve='u=(1/2+s/2-s^2)/D; v=(1/4+s-5s^2/4)/D',
        material='0<=u<=1/2; 0<=v<=1/4; 9(1-4v)(u-v)-(2v-u)^2>=0',
        restriction='F(t,7/32)=(t-1/4)(7/4-t)',
        completeTuples='(t,t,7/32), 1/4<=t<=1/2', xyz='(t,7/32,0)', imageDimension=1,fiberDimension=0,
        incidents=[dict(t='1/4',loop=0,curve=2,originalParameter='1/2'),dict(t='1/2',loop=0,curve=1,originalParameter='7/8')]),
    noNewFoundation=True, noProductionChanges=True, noPriorSuccessReplay=True))
admit(out / 'frozen-input.json', sha(out / 'frozen-input.json'))
save('admission.json', dict(priorReceipt=str(prior_path), priorSHA256=expected_prior, checks=checks,
    selectedCompileSources=[name for name in link if name.endswith('.swift')],
    adapterSourceDifference=[], reusedProductionSources=prior['freshProduction'],
    scope='Only selected observation fixture and unchanged four M6 helpers; link admitted Native adapters and lower products; one runtime public clip call.'))


def execute(label, command):
    recheck()
    started = time.monotonic()

    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (args.timeout, args.timeout))

    process = subprocess.Popen(['/usr/bin/time', '-l', *command], cwd=root,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=True, preexec_fn=constrain)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        rows = subprocess.check_output(['ps', '-axo', 'pid,ppid,command'], text=True).splitlines()[1:]
        parsed = [row.split(None, 2) for row in rows]
        owned = {process.pid}
        for _ in range(len(parsed)):
            updated = owned | {int(row[0]) for row in parsed if len(row) == 3 and int(row[1]) in owned}
            if updated == owned:
                break
            owned = updated
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        for pid in owned:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stdout, stderr = process.communicate()
    log = out / (label + '.log')
    log.write_text(stdout + stderr + ('\nOwned process timed out and was reaped.\n' if timed_out else ''))
    rss = re.search(r'(\d+)\s+maximum resident set size', stderr)
    record = dict(label=label,command=command,measuredCommand=['/usr/bin/time','-l',*command],
        timeoutSeconds=args.timeout,cpuLimitSeconds=args.timeout,elapsedSeconds=time.monotonic()-started,
        exitCode=process.returncode,timedOut=timed_out,logSHA256=sha(log),
        maximumResidentSetBytes=int(rss[1]) if rss else None)
    runs.append(record)
    save('runs.json', runs)
    print(label, 'exit', record['exitCode'], 'seconds', round(record['elapsedSeconds'],3),
        'rssBytes',record['maximumResidentSetBytes'],flush=True)
    recheck()
    if timed_out or process.returncode:
        save('failure.json',dict(state='observed-process-failure',label=label,checks=checks,products=products,runs=runs))
        print((stdout+stderr)[-9000:],flush=True)
        raise SystemExit(1)
    return stdout


execute('compile-link-observation',link)
products[str(proof)] = sha(proof)
stdout = execute('runtime-observation',[str(proof)])
stop = 'OBSERVED_TYPED_STOP stage public-clip cause unsupportedCoverage' in stdout
success = 'OBSERVED_COMPLETE_SUCCESS independent whole-cell tuple iff' in stdout
assert stop != success, stdout
save('receipt.json',dict(cell='B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01',lane='native',head=head,
    state='observed-public-unsupportedCoverage' if stop else 'observed-complete-public-success',
    exactValidationReached='REACHED exact validated face' in stdout,
    publicClipCalls=stdout.count('CALL DefaultOriginalFaceBoundaryClipper.clip'),
    typedStop='NativeExactRelationFailure.unsupportedCoverage' if stop else None,
    noClippedSuccess=stop,checks=checks,products=products,runs=runs,
    priorReceipt=str(prior_path),priorSHA256=expected_prior,adapterSourceDifference=[],
    scope='One fixed genuine rational quadratic closed face material observation; no general rational winding acceptance.'))
recheck()
print(stdout,flush=True)
print('RECEIPT',out / 'receipt.json',sha(out / 'receipt.json'),flush=True)
