#!/usr/bin/env python3
"""Execute one complete Native collapsed-boundary cell with admitted lower products."""
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
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--timeout', type=int, default=120)
parser.add_argument('--reuse-domain', type=Path)
args = parser.parse_args()
assert args.timeout > 0
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
prior_dir = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/B-COONS-HOLE-01' / ('native-regression-' + args.lane)
prior_path = prior_dir / 'receipt.json'
prior = json.loads(prior_path.read_text())
checks, fresh, products, runs = {}, {}, {}, []


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
    for name, expected in fresh.items():
        assert sha(name) == expected, name
    for name, expected in products.items():
        assert sha(name) == expected, name


admit(prior_path, sha(prior_path))
changed = root / 'Sources/CADGeometry/NativeExactRelations/DefaultNativeExactRelationFamilyResolver.swift'
for group in ['inputs', 'premises', 'cached', 'artifacts', 'products']:
    for name, expected in prior[group].items():
        if Path(name) == changed:
            old = subprocess.run(['git', 'show', '06f9d8da:' + str(changed.relative_to(root))],
                cwd=root, capture_output=True, check=True, timeout=30).stdout
            assert hashlib.sha256(old).hexdigest() == expected
            snapshot = out / 'historical-DefaultNativeExactRelationFamilyResolver.swift'
            snapshot.write_bytes(old)
            admit(snapshot, expected)
        else:
            admit(name, expected)
for name, expected in prior['logs'].items():
    admit(prior_dir / name, expected)

old_module = next(run['command'] for run in prior['runs'] if run['label'] == 'NativeDomainAdapters')
old_link = next(run['command'] for run in prior['runs'] if run['label'] == 'link-boundary')
old_work = Path(old_module[old_module.index('-emit-module-path') + 1]).parent
selected = [Path(name) for name in old_module if name.endswith('.swift')]
assert len(selected) == 32 and changed in selected
for path in selected:
    fresh[str(path)] = sha(path)
    if path != changed:
        assert prior['inputs'][str(path)] == fresh[str(path)]
fixture = root / 'Tests/OriginalPublicAcceptanceVerification/NativeCollapsedBoundaryAcceptance.swift'
helpers = sorted((root / 'Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryFixtures').glob('*.swift'))
assert len(helpers) == 4
for path in helpers:
    admit(path, prior['inputs'][str(path)])
admit(fixture, sha(fixture))
driver = out / 'driver.py'
shutil.copyfile(__file__, driver)
admit(driver, sha(driver))
admit(Path(__file__).resolve(), sha(__file__))
compiler = Path(old_module[0])
assert 'swift-6.4.0-RELEASE.xctoolchain' in str(compiler)
admit(compiler, sha(compiler))
admit(compiler.with_name('swift-frontend'), sha(compiler.with_name('swift-frontend')))
time_binary = Path('/usr/bin/time')
admit(time_binary, sha(time_binary))
portable = args.lane in {'wasm', 'embedded'}
if portable:
    assert '-resource-dir' in old_module
    sdk = old_module[old_module.index('-resource-dir') + 1]
    assert 'swift-6.4.0-RELEASE_wasm.artifactbundle' in sdk
if args.lane == 'embedded':
    assert 'Embedded' in old_module and '-whole-module-optimization' in old_module
if args.lane == 'asan':
    assert '-sanitize=address' in old_module and '-sanitize=address' in old_link

save('admission.json', dict(checks=checks, freshProduction=fresh,
    priorReceipt=str(prior_path), priorSHA256=sha(prior_path), lane=args.lane,
    selectedProductionSources=len(selected), selectedFixtureSources=len(helpers) + 1,
    onlyHistoricalSourceDifference=str(changed), historicalCommit='06f9d8da',
    scope='Current Native source/DI/L5 -> exact-validated Native Kernel face clipper only; no Coons issued graph, M5, ordinary XYZ or broad rebuild.'))


def execute(label, command):
    recheck()
    started = time.monotonic()
    cpu_limit = args.timeout

    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (cpu_limit, cpu_limit))

    process = subprocess.Popen([str(time_binary), '-l', *command], cwd=root,
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
            additions = {int(row[0]) for row in parsed if len(row) == 3 and int(row[1]) in owned}
            updated = owned | additions
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
    record = dict(label=label, command=command, measuredCommand=[str(time_binary), '-l', *command],
        timeoutSeconds=args.timeout, cpuLimitSeconds=cpu_limit, elapsedSeconds=time.monotonic() - started,
        exitCode=process.returncode, timedOut=timed_out, logSHA256=sha(log),
        maximumResidentSetBytes=int(rss[1]) if rss else None)
    runs.append(record)
    save('runs.json', runs)
    print(label, 'exit', record['exitCode'], 'seconds', round(record['elapsedSeconds'], 3),
        'rssBytes', record['maximumResidentSetBytes'], flush=True)
    recheck()
    if timed_out or process.returncode:
        save('failure.json', dict(state='observed-failure', lane=args.lane, label=label,
            log=str(log), logSHA256=sha(log), checks=checks, freshProduction=fresh, runs=runs))
        print((stdout + stderr)[-9000:], flush=True)
        raise SystemExit(1)


module = list(old_module)
module[1:1] = ['-j2', '-I', str(old_work)]
for index, token in enumerate(module):
    if token == str(old_work):
        # The added old-work import remains as the admitted source adapter fallback.
        if index > 5:
            module[index] = str(out)
    elif token == str(old_work / 'NativeDomainAdapters.swiftmodule'):
        module[index] = str(out / 'NativeDomainAdapters.swiftmodule')
    elif token == str(old_work / 'libNativeDomainAdapters.a'):
        module[index] = str(out / 'libNativeDomainAdapters.a')
domain_dir = out
if args.reuse_domain:
    domain_dir = args.reuse_domain.resolve()
    previous_path = domain_dir / 'module-receipt.json'
    previous = json.loads(previous_path.read_text())
    admit(previous_path, sha(previous_path))
    assert previous['lane'] == args.lane and previous['freshProduction'] == fresh
    for name, expected in previous['checks'].items():
        admit(name, expected)
    for name, expected in previous['products'].items():
        admit(name, expected)
    for record in previous['runs']:
        assert record['exitCode'] == 0
        admit(domain_dir / (record['label'] + '.log'), record['logSHA256'])
else:
    execute('compile-current-native-domain', module)
    for name in ['NativeDomainAdapters.swiftmodule', 'libNativeDomainAdapters.a']:
        products[str(out / name)] = sha(out / name)
    module_checks = {name: value for name, value in checks.items()
        if name not in {str(fixture), str(driver), str(Path(__file__).resolve())}}
    save('module-receipt.json', dict(lane=args.lane, freshProduction=fresh,
        checks=module_checks, products=products, runs=runs))

proof = out / ('NativeCollapsedBoundaryProof.wasm' if portable else 'NativeCollapsedBoundaryProof')
link = list(old_link)
link[1:1] = ['-j2', '-I', str(domain_dir), '-D', 'NATIVE_DOMAIN_ISOLATED_VERIFICATION']
old_proof = next(name for name in link if name.endswith('/M6BoundaryProof/Proof.swift'))
index = link.index(old_proof)
link[index:index + 1] = [str(fixture), *map(str, helpers)]
link.remove(str(old_work / 'libNativeExactBoundaryFixtures.a'))
link[link.index(str(old_work / 'libNativeDomainAdapters.a'))] = str(domain_dir / 'libNativeDomainAdapters.a')
link[link.index('-o') + 1] = str(proof)
execute('compile-link-cell', link)
products[str(proof)] = sha(proof)
runtime = [str(proof)]
if portable:
    old_runtime = next(run['command'] for run in prior['runs'] if run['label'] == 'boundary-seamPole')
    runtime = old_runtime[:2] + runtime + ['all']
    for name in runtime[:2]:
        assert str(name) in checks, 'Runtime must match an admitted receipt: ' + str(name)
save('ready-to-run.json', dict(lane=args.lane, checks=checks, freshProduction=fresh,
    products=products, runtime=runtime, runs=runs))
execute('runtime-cell', runtime)
recheck()
save('receipt.json', dict(state='complete-collapsed-boundary-cell-verified', lane=args.lane,
    checks=checks, freshProduction=fresh, products=products, runs=runs,
    priorReceipt=str(prior_path), priorSHA256=sha(prior_path),
    selectedProductionSources=len(selected), selectedFixtureSources=len(helpers) + 1,
    scope='B-NATIVE-COLLAPSED-CLOSED-01 exact current Native CS and validated Kernel clipper: complete raw/refined terminal-cell iff, every ordinal, bottom/two-corner incidences and post-scope owner; zero work/storage, entry/final cancellation and complete empty out-of-support request. Image0/fiber2 are oracle meaning, not published fields. Whole-cost N/N-1 not measured.'))
print('PASS', args.lane, 'B-NATIVE-COLLAPSED-CLOSED-01', flush=True)
