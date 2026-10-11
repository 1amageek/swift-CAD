"""Run the immutable pre-F1 candidate; never certify the current production root."""
import difflib
import hashlib
import json
import os
import resource
import signal
import subprocess
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
module = root / '.build/s-coons-aux-green-embedded-20261011-v1'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(path):
    return json.loads(Path(path).read_text())

def save(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')

admission_path = out / 'admission.json'
module_receipt_path = module / 'module-receipt.json'
compile_runs_path = out / 'runs.json'
admission = read(admission_path)
module_receipt = read(module_receipt_path)
compile_runs = read(compile_runs_path)
assert module_receipt['freshProduction'] == admission['freshProduction']
assert len(compile_runs) == 1
compile_run = compile_runs[0]
assert compile_run['label'] == 'compile-link-proof' and compile_run['exitCode'] == 0
assert sha(out / 'compile-link-proof.log') == compile_run['logSHA256']
product = out / 'Proof.wasm'
assert compile_run['command'][-2:] == ['-o', str(product)]

checks = dict(admission['checks'])
for name, expected in module_receipt['checks'].items():
    assert name not in checks or checks[name] == expected
    checks[name] = expected
for run in module_receipt['runs']:
    assert run['exitCode'] == 0
    log = module / (run['label'] + '.log')
    assert sha(log) == run['logSHA256']
    checks[str(log)] = run['logSHA256']
port = read(root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-COINC-01/embedded/port-command.json')
producer = next(Path(name) for name in port if name.endswith('OriginalRetainedLiftPlanePublicProducer.swift'))
prefix = producer.read_text().split('///', 1)[0].encode()
historical_sources = []
source_differences = []
for original, expected in admission['freshProduction'].items():
    name = Path(original).name
    if name == 's-coons-identity-compiler-auxiliary-candidate.swift':
        name = 'OriginalIssuedGraphSelfIdentityCompiler.swift'
    generated = out / name
    reused = module / name
    generated_bytes = generated.read_bytes()
    assert generated_bytes.startswith(prefix)
    body = generated_bytes[len(prefix):]
    assert hashlib.sha256(body).hexdigest() == expected
    assert generated_bytes == reused.read_bytes()
    historical_sources.append(dict(originalPath=original, historicalBodySHA256=expected,
        generatedPath=str(generated), generatedSHA256=sha(generated), reusedGeneratedPath=str(reused)))
    current = Path(original).read_bytes()
    if current != body:
        source_differences.append(dict(path=original, historicalSHA256=expected,
            currentSHA256=sha(original), diff=''.join(difflib.unified_diff(
                body.decode().splitlines(True), current.decode().splitlines(True),
                fromfile='historical/' + name, tofile='current/' + name))))
assert {Path(item['path']).name for item in source_differences} == {
    'OriginalIssuedGraphSelfContactQuerying.swift', 'DefaultOriginalIssuedGraphSelfContactQuery.swift'}

fixture = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsGraphSelfContactFoldScope.swift'
assert sha(fixture) == 'c25a04e48b9b3dc29442f156d39cc6f7a8d174a4cbeb2f453f1dddc6284dc92c'
assert (out / fixture.name).read_bytes() == prefix + fixture.read_bytes()
probe = root / 'Tests/OriginalPublicAcceptanceVerification/CoonsGraphSelfContactProbe.swift'
support = probe.read_text().replace('@main struct CoonsGraphSelfContactProbe', 'struct CoonsGraphSelfContactProbe')
support = support[:support.index('    static func main() throws {')] + '}\n'
support = support.replace('import NativeDomainAdapters\n', '')
assert (out / 'Support.swift').read_bytes() == prefix + support.encode()
fixture_text = fixture.read_text()
nonempty_assertion = 'try PolylineLiftProof.require(family.graphs.count == (collapsed ? 1 : 2))'
same_family_call = 'first: family, second: family, maximumPairs: collapsed ? 1 : 4'
assert nonempty_assertion in fixture_text and same_family_call in fixture_text
assert fixture_text.index(nonempty_assertion) < fixture_text.index(same_family_call)
assert 'let raw = try raw(collapsed: collapsed, using: &preparation)' in fixture_text

runtime_receipt = root / 'Tests/OriginalNativeConsumerIntakeVerification/Evidence/embedded-query-field-accepted/receipt.json'
runtime_inputs = read(runtime_receipt)['inputs']
runner = root / 'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'
for path in ['/usr/local/bin/node', str(runner)]:
    assert sha(path) == runtime_inputs[path]
    checks[path] = runtime_inputs[path]
for path in [admission_path, module_receipt_path, compile_runs_path, out / 'compile-link-proof.log',
             out / 'driver.py', fixture, probe, out / fixture.name, out / 'Support.swift',
             runtime_receipt, product, Path(__file__)]:
    actual = sha(path)
    assert str(path) not in checks or checks[str(path)] == actual
    checks[str(path)] = actual
snapshots_path = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-POLY-01-ordinary/embedded/compiler-source-snapshot.json'
snapshots = read(snapshots_path)
linked_archive_correspondence = []
for argument in compile_run['command']:
    if argument.endswith(('.swift', '.a')):
        if argument not in checks and argument in snapshots:
            expected = snapshots[argument]['sha256']
            assert sha(argument) == expected, argument
            checks[argument] = expected
        if argument not in checks and argument.endswith('.a'):
            actual = sha(argument)
            matches = [name for name, expected in checks.items()
                if Path(name).name == Path(argument).name and expected == actual]
            assert len(matches) == 1, argument
            linked_archive_correspondence.append(dict(linkedPath=argument,
                admittedSnapshotPath=matches[0], sha256=actual))
            checks[argument] = actual
        assert str(Path(argument)) in checks, argument

def verify():
    for path, expected in checks.items():
        assert sha(path) == expected, path

argv = ['/usr/local/bin/node', str(runner), str(product), 'all']
metadata = dict(state='historical-candidate-admitted', lane='embedded', currentRootAccepted=False,
    scope='Pre-F1 candidate, nonempty issued Native folded and scoped-collapse graph families only; no empty-family claim.',
    checks=checks, historicalSources=historical_sources, currentRootDifferences=source_differences,
    compositionalReuse=dict(reason='F1 adds cover authority and admission for empty graph families. Both fixture families are the same nonempty family; the existing graph request supplies the reference and empty-family branches are not executed.',
        fixture=str(fixture), assertion=nonempty_assertion, sameFamilyCall=same_family_call),
    successfulCompile=compile_run, reusedModuleCompileRuns=module_receipt['runs'],
    linkedArchiveCorrespondence=linked_archive_correspondence,
    runtime=argv, timeoutSeconds=360, cpuLimitSeconds=360)
verify()
save(out / 'historical-runtime-admission.json', metadata)
checks[str(out / 'historical-runtime-admission.json')] = sha(out / 'historical-runtime-admission.json')

def constrain():
    resource.setrlimit(resource.RLIMIT_CPU, (360, 360))

start = time.monotonic()
log = out / 'historical-runtime-all.log'
with log.open('x') as stream:
    with subprocess.Popen(argv, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
            start_new_session=True, preexec_fn=constrain) as process:
        try:
            code = process.wait(timeout=360)
        except subprocess.TimeoutExpired:
            code = 'timeout'
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
elapsed = time.monotonic() - start
verify()
receipt = metadata | dict(state='historical-candidate-runtime-verified' if code == 0 else 'historical-candidate-runtime-failed',
    run=dict(command=argv, exitCode=code, elapsedSeconds=elapsed, timeoutSeconds=360, cpuLimitSeconds=360,
        processGroupCleanup=True, log=str(log), logSHA256=sha(log)), preAndPostChecksPassed=True)
save(out / 'historical-runtime-receipt.json', receipt)
print('historical-runtime-all', code, round(elapsed, 3), flush=True)
print(log.read_text(), flush=True)
if code != 0:
    raise SystemExit(1)
