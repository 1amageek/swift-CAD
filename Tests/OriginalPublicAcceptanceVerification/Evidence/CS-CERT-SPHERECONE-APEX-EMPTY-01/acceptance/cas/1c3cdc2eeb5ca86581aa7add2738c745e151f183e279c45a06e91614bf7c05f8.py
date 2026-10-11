#!/usr/bin/env python3
"""Verify the original certified apex exclusion using the retained four-lane authority stack."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--groups', default='complete')
parser.add_argument('--reuse-source', type=Path)
parser.add_argument('--reuse-product', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
assert out.is_relative_to(root / '.build'), 'Compiler products must remain ignored.'
out.mkdir(parents=True, exist_ok=False)
checks, fresh, products, runs = {}, {}, {}, []

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(path):
    return json.loads(Path(path).read_text())

def save(name, value):
    (out / name).write_text(json.dumps(value, indent=2) + '\n')

def admit(path, expected):
    path = Path(path)
    assert path.is_file() and sha(path) == expected, 'Receipt premise differs: ' + str(path)
    checks[str(path)] = expected

def recheck():
    for mapping in [checks, fresh, products]:
        for path, expected in mapping.items():
            assert sha(path) == expected, 'Changed admitted input: ' + path

def execute(label, command):
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (120, 120))
    log = out / (label + '.log')
    started = time.monotonic()
    descendants, peak_rss, cpu_by_pid = set(), 0, {}
    with log.open('w') as stream:
        with subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=constrain) as process:
            def sample():
                nonlocal peak_rss
                rows = [line.split() for line in subprocess.check_output(
                    ['ps', '-axo', 'pid=,ppid=,rss=,time='], text=True, timeout=5).splitlines() if line.strip()]
                owners = {process.pid} | descendants
                while True:
                    found = {int(pid) for pid, parent, rss, cpu in rows if int(parent) in owners}
                    if found <= owners:
                        break
                    owners |= found
                descendants.update(owners - {process.pid})
                peak_rss = max(peak_rss, sum(int(rss) for pid, parent, rss, cpu in rows if int(pid) in owners))
                for pid, parent, rss, cpu in rows:
                    if int(pid) in owners:
                        seconds = sum(float(value) * 60 ** index for index, value in enumerate(reversed(cpu.split(':'))))
                        cpu_by_pid[int(pid)] = max(cpu_by_pid.get(int(pid), 0), seconds)
                return {int(pid) for pid, parent, rss, cpu in rows}
            stop = None
            try:
                while process.poll() is None:
                    sample()
                    if time.monotonic() - started >= 120:
                        stop = 'wall-limit'
                    elif sum(cpu_by_pid.values()) >= 120:
                        stop = 'sampled-owned-cpu-limit'
                    if stop:
                        break
                    try:
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
            finally:
                survivors = descendants & sample()
                if stop or survivors:
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
        elapsedSeconds=time.monotonic() - started, wallLimitSeconds=120, cpuLimitSecondsPerProcess=120,
        sampledOwnedCPULimitSeconds=120, sampledCPUSeconds=sum(cpu_by_pid.values()),
        peakOwnedProcessResidentSumKiB=peak_rss, ownedDescendantsRemaining=sorted(remaining), logSHA256=sha(log))
    runs.append(record)
    save('runs.json', runs)
    admit(log, record['logSHA256'])
    print(label, process.returncode, round(record['elapsedSeconds'], 3), flush=True)
    assert not remaining, record
    return process.returncode

# Admit the existing full authority chain, not just imported module bytes.
for owned in [Path(__file__).resolve(), Path(__file__).with_suffix('.swift')]:
    (out / owned.name).write_bytes(owned.read_bytes())
    admit(owned, sha(owned))
    admit(out / owned.name, sha(owned))

version = '10' if args.lane == 'native' else '1'
prior_path = root / f'.build/cs-angular-physical-acceptance-{args.lane}-20261012-v{version}/receipt.json'
prior = read(prior_path)
assert prior['success'] and prior['lane'] == args.lane
admit(prior_path, sha(prior_path))
for path, expected in prior['checks'].items():
    admit(path, expected)
for path, expected in prior['products'].items():
    admit(path, expected)
source_names = ['OriginalCertifiedSphereConeApexSnapshot', 'OriginalCertifiedSphereConeApexSnapshotProvider',
    'OriginalCertifiedSphereConeApexPlaneSeparationIssuing', 'OriginalCertifiedSphereConeApexPlaneSeparationReceipt',
    'DefaultOriginalCertifiedSphereConeApexPlaneSeparationIssuer']
upper_names = ['NativeExactRelations/OriginalCertifiedApexPlaneExclusion.swift',
    'NativeExactGeometricRelations/OriginalCertifiedApexPlaneExclusionReading.swift',
    'NativeExactGeometricRelations/OriginalCertifiedApexPlanePublicProducer.swift']
source_directory = root / 'Sources/CADGeometry/OriginalSourceIssuance'
source_files = [source_directory / (name + '.swift') for name in source_names]
old = next(run['command'] for run in prior['runs'] if run['label'] == 'compile-link')
flags = old[:old.index('-emit-executable')]
flags[flags.index('-module-cache-path') + 1] = str(out / 'module-cache')
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
assert (args.lane == 'embedded') == ('Embedded' in flags)
assert ('-sanitize=address' in flags) == (args.lane == 'asan')
assert flags[flags.index('-target')+1] == ('wasm32-unknown-wasip1' if args.lane in {'wasm', 'embedded'} else 'arm64-apple-macos15.0')
archives = [value for value in old if value.endswith('.a')]
for archive in archives:
    admit(archive, prior['products'].get(archive, prior['checks'].get(archive)))
old_proof = Path(next(path for path in old if path.endswith('/Proof.swift')))
old_fixture = root / 'Tests/OriginalPublicAcceptanceVerification/AngularPhysicalArcPlaneAcceptance.swift'
proof_text = old_proof.read_text()
assert proof_text.endswith(old_fixture.read_text())
prefix = proof_text[:-len(old_fixture.read_text())]
prefix = prefix.replace('import struct RetainedHostAdapters.OriginalSourceProofAdmission\n',
    'import struct AngularSourcePhase.OriginalSourceProofAdmission\n')
# The current mapper already explicitly names the retained failure owners.
assert 'import enum DraftZeroRuledPort.NativeExactGeometricRelationFailure' in prefix
host_path = root / f'Tests/OriginalDerivativeLiftHostVerification/Evidence/{args.lane}/receipt.json'
host = read(host_path)
admit(host_path, prior['checks'][str(host_path)])
retained = {}
for path, expected in host['inputs'].items():
    candidate = Path(path)
    if candidate.is_relative_to(source_directory / 'OriginalPhysicalAngle') or candidate.name in {
            'CanonicalAnalyticSurface.swift', 'AnalyticBasis.swift'} and candidate.is_relative_to(root / 'Sources'):
        admit(candidate, expected)
        retained[path] = expected
assert len([path for path in retained if '/OriginalPhysicalAngle/' in path]) == 8
observation_path = root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/native-observation-20261013-v2/receipt.json'
admit(observation_path, '9e5082d2e62797ce544d4da4d4dd42b44c86b48772fca842429cd45b74de8765')
observation = read(observation_path)
for path, expected in observation['unchangedSelectedCachedSources'].items():
    if not path.endswith('/CertifiedSphereConeIntersectionCurve.swift'):
        admit(path, expected)

# Keep the original nominal type: extract its actual private helper declarations.
curve_source = root / 'Sources/CADGeometry/CertifiedSphereConeIntersectionCurve.swift'
text = curve_source.read_text()
fresh[str(curve_source)] = sha(curve_source)

def method(source, token):
    start = source.index(token)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return start, end

ranges = []
def select(start, end, kind):
    body = text[start:end]
    ranges.append(dict(kind=kind, firstLine=text[:start].count('\n')+1, lastLine=text[:end].count('\n')+1,
        sha256=hashlib.sha256(body.encode()).hexdigest(), bytes=len(body.encode())))
    return body
helper_start = text.index('    private struct TrigonometricPolynomial {')
helper_end = text.index('    private struct ScalarDifferential {', helper_start)
helpers = select(helper_start, helper_end, 'actual-nested-helper-declarations')
for token in ['    private static func makeConfiguration(', '    private static func canonicalCone(',
        '    private static func isNegative(']:
    start, end = method(text, token)
    helpers += select(start, end, token.strip()) + '\n'
port_start, port_end = method(text, '    func originalApexReducedSourceSnapshot(')
port = select(port_start, port_end, 'actual-new-source-snapshot-port')
port_wrapper = text.rindex('\nextension CertifiedSphereConeIntersectionCurve {', 0, port_start)
original_bytes = (text[:port_wrapper].rstrip('\n') + '\n').encode()
assert hashlib.sha256(original_bytes).hexdigest() == observation['unchangedSelectedCachedSources'][str(curve_source)], 'Cached curve changed beyond additive source port.'
source_out = out / 'source'
source_out.mkdir()
port_path = source_out / 'CertifiedApexSourcePayload.swift'
header = text[:text.index('public struct CertifiedSphereConeIntersectionCurve:')]
port_path.write_text(prefix + header + 'extension CADGeometry.CertifiedSphereConeIntersectionCurve {\n'
    + helpers + port + '\n}\n')
admit(port_path, sha(port_path))
save('selected-source-ranges.json', dict(originalPath=str(curve_source), currentSHA256=sha(curve_source),
    cachedSHA256=observation['unchangedSelectedCachedSources'][str(curve_source)],
    generatedPath=str(port_path), generatedSHA256=sha(port_path), ranges=ranges,
    typeAuthority='Imported cached CADGeometry.CertifiedSphereConeIntersectionCurve; no type/storage/constructor redeclaration.'))

# Archive exact bytes before any compilation; body prefixes are separately recorded.
def generated(original, body_prefix, directory):
    fresh[str(original)] = sha(original)
    snapshot = out / 'production-snapshot' / original.relative_to(root)
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    snapshot.write_bytes(original.read_bytes())
    admit(snapshot, fresh[str(original)])
    target = directory / original.name
    target.write_text(body_prefix + original.read_text())
    admit(target, sha(target))
    return str(target)

curve_snapshot = out / 'production-snapshot' / curve_source.relative_to(root)
curve_snapshot.parent.mkdir(parents=True, exist_ok=True)
curve_snapshot.write_bytes(curve_source.read_bytes())
admit(curve_snapshot, fresh[str(curve_source)])
source_inputs = [generated(path, prefix, source_out) for path in source_files] + [str(port_path)]
source_expected = {str(path): fresh[str(path)] for path in source_files + [curve_source]}
source_command = flags + ['-parse-as-library', '-enable-testing', '-emit-module', '-emit-library', '-static',
    '-module-name', 'CertifiedApexSourcePhase', *source_inputs,
    '-emit-module-path', str(source_out / 'CertifiedApexSourcePhase.swiftmodule'),
    '-o', str(source_out / 'libCertifiedApexSourcePhase.a')]
save('source-command.json', source_command)
upper_prefix = prefix + '\n@testable import CertifiedApexSourcePhase\n'
angular_source_names = {'OriginalAnalyticCosineZeroRoot.swift', 'OriginalAnalyticCosineZeroIssuing.swift',
    'OriginalAnalyticCosineZeroReceipt.swift', 'DefaultOriginalAnalyticCosineZeroIssuer.swift',
    'OriginalSourceProofAdmission.swift', 'OriginalAnalyticCoordinateSnapshot.swift',
    'OriginalAnalyticCoordinateCurveSnapshotProvider.swift', 'OriginalPlaneSnapshot.swift', 'OriginalPlaneSnapshotProvider.swift'}
angular_source_paths = {str(source_directory / name) for name in angular_source_names}
assert angular_source_paths <= set(prior['freshProduction'])
upper_paths = [Path(path) for path in prior['freshProduction'] if path not in angular_source_paths]
assert len(upper_paths) == 36
upper_paths += [root / 'Sources/CADGeometry' / relative for relative in upper_names + [
    'DefaultSurfaceSurfaceIntersector.swift', 'PlanePlaneSurfaceIntersector.swift']]
assert len(upper_paths) == len(set(upper_paths)) == 41
upper_directory = out / 'upper'
upper_directory.mkdir()
upper_expected = {str(path): sha(path) for path in upper_paths}
state = 'assembly-prepared'
try:
    if args.reuse_source:
        source_out = args.reuse_source.resolve()
        receipt_path = source_out.parent / 'source-receipt.json'
        previous = read(receipt_path)
        admit(receipt_path, sha(receipt_path))
        assert previous['lane'] == args.lane and previous['freshProduction'] == source_expected
        assert previous['prefixSHA256'] == hashlib.sha256(prefix.encode()).hexdigest()
        for path, expected in previous['checks'].items():
            if path != str(Path(__file__)) and not path.endswith('/CertifiedSphereConeApexEmptyAcceptance.swift'):
                admit(path, expected)
        for path, expected in previous['products'].items():
            admit(path, expected)
    else:
        recheck()
        assert execute('compile-source', source_command) == 0
        source_products = {str(source_out / name): sha(source_out / name)
            for name in ['CertifiedApexSourcePhase.swiftmodule', 'libCertifiedApexSourcePhase.a']}
        products.update(source_products)
        save('source-receipt.json', dict(lane=args.lane, freshProduction=source_expected,
            prefixSHA256=hashlib.sha256(prefix.encode()).hexdigest(), products=source_products,
            checks=checks.copy(), runs=[runs[-1]]))
    inputs = []
    for original in upper_paths:
        body_prefix = upper_prefix
        if original.name in {'NativeExactPublicCurveSurfaceProducer.swift', 'NativeExactCurveSurfacePointProducer.swift',
                'DefaultCurveSurfaceIntersector+CurveSurfaceGeometry.swift', 'DefaultCurveSurfaceIntersector+ExactRelation.swift'}:
            body_prefix = 'import CADCore\n@testable import CADGeometry\n'
        if original.name in {'DefaultSurfaceSurfaceIntersector.swift', 'PlanePlaneSurfaceIntersector.swift'}:
            body_prefix = 'import CADCore\n@testable import CADGeometry\n@testable import PublicLiftPlane\nimport enum PublicLiftPlane.GeometryExactScalarFailure\n'
        inputs.append(generated(original, body_prefix, upper_directory))
    adapter = Path(next(path for path in old if path.endswith('/ActualSelectorDeclineAdapters.swift')))
    admit(adapter, prior['checks'][str(adapter)])
    inputs.append(str(adapter))
    fixture = Path(__file__).with_suffix('.swift')
    for path in [fixture, Path(__file__).resolve()]:
        admit(path, sha(path))
        target = out / path.name
        target.write_bytes(path.read_bytes())
        admit(target, sha(target))
    proof = out / 'Proof.swift'
    proof.write_text(upper_prefix + fixture.read_text())
    admit(proof, sha(proof))
    product = out / ('Acceptance.wasm' if args.lane in {'wasm', 'embedded'} else 'Acceptance')
    command = flags + ['-I', str(source_out), '-emit-executable', '-module-name', 'CertifiedSphereConeApexEmptyAcceptance',
        *inputs, str(proof), *archives, str(source_out / 'libCertifiedApexSourcePhase.a'), '-o', str(product)]
    if args.lane == 'embedded' and '-lc++abi' not in command:
        command += ['-Xlinker', '-lc++abi']
    save('compile-command.json', command)
    recheck()
    if args.reuse_product:
        product = args.reuse_product.resolve()
        assembly_path = product.parent / 'receipt.json'
        assembly = read(assembly_path)
        assert assembly['lane'] == args.lane and assembly['freshProduction'] == fresh
        assert sha(product.parent / fixture.name) == sha(fixture)
        admit(assembly_path, sha(assembly_path))
        for path, expected in assembly['checks'].items():
            if path != str(Path(__file__).resolve()):
                admit(path, expected)
        for path, expected in assembly['products'].items():
            admit(path, expected)
        save('reused-assembly.json', dict(receipt=str(assembly_path), sha256=sha(assembly_path),
            product=str(product), productSHA256=assembly['products'][str(product)],
            fixtureSHA256=sha(fixture), freshProduction=fresh))
        recheck()
    else:
        assert execute('compile-link', command) == 0
    products[str(product)] = sha(product)
    state = 'compiled'
    runtime = [str(product)]
    if args.lane in {'wasm', 'embedded'}:
        node = Path('/usr/local/bin/node')
        admit(node, prior['checks'][str(node)])
        wasi = out / 'run.mjs'
        wasi.write_text('import {readFile} from "node:fs/promises";\nimport {WASI} from "node:wasi";\n'
            'const [path,group]=process.argv.slice(2);\n'
            'const wasi=new WASI({version:"preview1",args:[path,group],env:{CAD_PROOF_GROUP:group},preopens:{},returnOnExit:true});\n'
            'const module=await WebAssembly.compile(await readFile(path));\n'
            'const instance=await WebAssembly.instantiate(module,wasi.getImportObject());\n'
            'const code=wasi.start(instance);if(code!==0)throw new Error(`WASI exit ${code}`);\n')
        admit(wasi, sha(wasi))
        runtime = [str(node), str(wasi), str(product)]
    for group in args.groups.split(','):
        recheck()
        assert execute('runtime-' + group, runtime + [group]) == 0
    state = 'accepted-selected-current-snapshot'
finally:
    recheck()
    save('receipt.json', dict(cell='CS-CERT-SPHERECONE-APEX-EMPTY-01', lane=args.lane,
        state=state, success=state == 'accepted-selected-current-snapshot', cellComplete=False,
        groups=args.groups.split(','), parentReceipt=str(prior_path), parentSHA256=sha(prior_path),
        retainedSourceContracts=retained, checks=checks, freshProduction=fresh, products=products, runs=runs,
        postHashesMatch=True, rebuiltLowerBodies=0, selectedSourceRanges=str(out / 'selected-source-ranges.json'),
        scope='Actual cached certified nominal + exact current helper/port ranges; retained source9 and current upper dispatch; no L5 solve for source separation.'))
print(state, flush=True)
