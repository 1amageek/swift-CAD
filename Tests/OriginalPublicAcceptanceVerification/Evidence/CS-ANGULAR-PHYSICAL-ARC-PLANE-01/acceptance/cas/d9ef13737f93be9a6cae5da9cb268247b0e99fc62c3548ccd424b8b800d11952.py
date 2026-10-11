#!/usr/bin/env python3
"""Verify the fixed physical angular cell over one admitted Revolution authority stack."""
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
                    ['ps', '-axo', 'pid=,ppid=,rss=,time='], text=True, timeout=120).splitlines() if line.strip()]
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
            timed_out = False
            while process.poll() is None:
                sample()
                if time.monotonic() - started >= 120:
                    timed_out = True
                    break
                try:
                    process.wait(timeout=0.25)
                except subprocess.TimeoutExpired:
                    pass
            survivors = descendants & sample()
            if timed_out or survivors:
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
    record = dict(label=label, command=command, exitCode=process.returncode, timedOut=timed_out,
        elapsedSeconds=time.monotonic() - started, wallLimitSeconds=120, cpuLimitSecondsPerProcess=120,
        sampledCPUSeconds=sum(cpu_by_pid.values()), peakOwnedProcessResidentSumKiB=peak_rss,
        ownedDescendantsRemaining=sorted(remaining), logSHA256=sha(log))
    runs.append(record)
    save('runs.json', runs)
    admit(log, record['logSHA256'])
    print(label, process.returncode, round(record['elapsedSeconds'], 3), flush=True)
    assert not remaining, record
    return process.returncode


version = '16' if args.lane == 'native' else '1'
prior_path = root / ('Tests/OriginalPublicAcceptanceVerification/Evidence/'
    f'CS-REVOLUTION-AXIS-FIBER-01/acceptance/{args.lane}-20261012-v{version}/receipt.json')
prior = read(prior_path)
assert prior['success'] and prior.get('lane', args.lane) == args.lane
admit(prior_path, sha(prior_path))
# Keep the admitted source/compiler/log chain beside the selected binary stack.
# Unrelated historical products are not rehashed or relabelled as current sources.
premise_paths = []
for path, expected in prior['checks'].items():
    candidate = Path(path)
    if candidate.suffix == '.log' or candidate.name.endswith('receipt.json'):
        admit(candidate, expected)
        premise_paths.append(path)
host_path = root / f'Tests/OriginalDerivativeLiftHostVerification/Evidence/{args.lane}/receipt.json'
host = read(host_path)
admit(host_path, prior['checks'][str(host_path)])
contract_names = {
    'OriginalPiGenerating.swift', 'OriginalPiOwner.swift', 'OriginalPiRefinement.swift',
    'OriginalPiValue.swift', 'OriginalPiScalarDomain.swift', 'OriginalPiScalarDomain+Arithmetic.swift',
    'OriginalPiScalarDomain+Ordering.swift', 'DefaultOriginalAnalyticCoordinateIssuer.swift',
    'DefaultOriginalAnalyticCoordinateIssuer+Physical.swift', 'DefaultOriginalPhysicalAnalyticCoordinateIssuer.swift',
    'DefaultOriginalPlaneBasisIssuer.swift', 'OriginalAnalyticCoordinateSnapshot.swift',
    'OriginalAnalyticCoordinateCurveSnapshotProvider.swift', 'OriginalPlaneSnapshot.swift',
    'OriginalPlaneSnapshotProvider.swift', 'OriginalSourceProofAdmission.swift',
    'DefaultOriginalAnalyticDomainIssuer.swift', 'OriginalAnalyticDomainCover.swift',
    'OriginalPlaneBasisReceipt+Coordinates.swift', 'DefaultOriginalPlaneDomainIssuer.swift'}
retained_contracts = {}
for path, expected in host['inputs'].items():
    candidate = Path(path)
    if candidate.name in contract_names and candidate.is_relative_to(root / 'Sources'):
        admit(candidate, expected)
        retained_contracts[path] = expected
assert {Path(path).name for path in retained_contracts} == contract_names
old = next(run['command'] for run in prior['runs'] if run['label'] == 'compile-link')
flags = old[:old.index('-emit-executable')]
cache_index = flags.index('-module-cache-path')
flags[cache_index + 1] = str(out / 'module-cache')
assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
assert (args.lane == 'embedded') == ('Embedded' in flags)
for tool in [Path(flags[0]), Path(flags[0]).with_name('swift-frontend')]:
    admit(tool, prior['checks'][str(tool)])
archives = [value for value in old if value.endswith('.a')]
for archive in archives:
    admit(archive, prior['checks'][archive])
# Admit only the actual imported modules and selected archives, not unrelated products.
module_names = {'CADCore', 'CADGeometry', 'RetainedHostAdapters', 'DerivativePayloadAccess',
    'PublicLiftPlane', 'DraftZeroRuledPort', 'GuideSeamPort', 'CallerAdapters', 'RuledObservationAdapters'}
for path, expected in prior['checks'].items():
    candidate = Path(path)
    if candidate.name.endswith('.swiftmodule') and (
            candidate.stem in module_names or candidate.parent.stem in module_names):
        admit(candidate, expected)

prior_proof = Path(next(path for path in old if path.endswith('/Proof.swift')))
prior_fixture = root / 'Tests/OriginalPublicAcceptanceVerification/RevolutionAxisFiberAcceptance.swift'
admit(prior_proof, prior['checks'][str(prior_proof)])
proof_bytes = prior_proof.read_text()
old_fixture_sha = prior['checks'][str(prior_fixture)]
fixture_bytes = prior_fixture.read_bytes()
assert hashlib.sha256(fixture_bytes).hexdigest() == old_fixture_sha
assert proof_bytes.endswith(fixture_bytes.decode())
prefix = proof_bytes[:-len(fixture_bytes.decode())]
prefix = prefix.replace('@testable import SourceIssuer\n', '')
source_prefix = prefix.split('\n@testable import DraftZeroRuledPort', 1)[0]
source_prefix = source_prefix.replace('import struct RetainedHostAdapters.OriginalSourceProofAdmission\n', '')
source_directory = root / 'Sources/CADGeometry/OriginalSourceIssuance'
source_names = ['OriginalAnalyticCosineZeroRoot', 'OriginalAnalyticCosineZeroIssuing',
    'OriginalAnalyticCosineZeroReceipt', 'DefaultOriginalAnalyticCosineZeroIssuer',
    'OriginalSourceProofAdmission', 'OriginalAnalyticCoordinateSnapshot',
    'OriginalAnalyticCoordinateCurveSnapshotProvider', 'OriginalPlaneSnapshot', 'OriginalPlaneSnapshotProvider']
source_files = [source_directory / (name + '.swift') for name in source_names]


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


source_out = out / 'source'
source_out.mkdir()
source_inputs = [generated(path, source_prefix, source_out) for path in source_files]
source_expected = {str(path): fresh[str(path)] for path in source_files}
source_command = flags + ['-parse-as-library', '-enable-testing', '-emit-module', '-emit-library', '-static',
    '-module-name', 'AngularSourcePhase', *source_inputs,
    '-emit-module-path', str(source_out / 'AngularSourcePhase.swiftmodule'),
    '-o', str(source_out / 'libAngularSourcePhase.a')]
save('source-command.json', source_command)

upper_directory = out / 'upper'
upper_directory.mkdir()
upper_prefix = prefix + '\n@testable import AngularSourcePhase\n'
for name in source_names:
    if name != 'OriginalSourceProofAdmission':
        kind = 'protocol' if name == 'OriginalAnalyticCosineZeroIssuing' else 'struct'
        upper_prefix += 'import ' + kind + ' AngularSourcePhase.' + name + '\n'
upper_paths = [Path(path) for path in prior['freshProduction']]
upper_paths += [root / 'Sources/CADGeometry' / relative for relative in [
    'NativeExactRelations/OriginalAngularPlaneRelations.swift',
    'NativeExactRelations/DefaultOriginalAngularPlaneRelationCompiler.swift',
    'NativeExactGeometricRelations/OriginalAngularPlaneRelationReading.swift',
    'NativeExactGeometricRelations/OriginalAngularPlaneGeometricRelations.swift',
    'NativeExactGeometricRelations/OriginalAngularPlanePublicProducer.swift',
    'NativeExactGeometricRelations/OriginalAngularPlaneExactPoint.swift']]
state = 'assembly-prepared'
try:
    if args.reuse_source:
        source_out = args.reuse_source.resolve()
        receipt_path = source_out.parent / 'source-receipt.json'
        previous = read(receipt_path)
        admit(receipt_path, sha(receipt_path))
        assert previous['lane'] == args.lane and previous['freshProduction'] == source_expected
        assert previous['prefixSHA256'] == hashlib.sha256(source_prefix.encode()).hexdigest()
        for path, expected in previous['products'].items():
            admit(path, expected)
    else:
        recheck()
        assert execute('compile-source', source_command) == 0
        source_products = {str(source_out / name): sha(source_out / name)
            for name in ['AngularSourcePhase.swiftmodule', 'libAngularSourcePhase.a']}
        products.update(source_products)
        save('source-receipt.json', dict(lane=args.lane, freshProduction=source_expected,
            prefixSHA256=hashlib.sha256(source_prefix.encode()).hexdigest(), products=source_products,
            checks=checks.copy(), runs=[runs[-1]]))
    inputs = []
    for original in upper_paths:
        body_prefix = upper_prefix
        if original.name in {'NativeExactPublicCurveSurfaceProducer.swift', 'NativeExactCurveSurfacePointProducer.swift',
                'DefaultCurveSurfaceIntersector+CurveSurfaceGeometry.swift', 'DefaultCurveSurfaceIntersector+ExactRelation.swift'}:
            body_prefix = 'import CADCore\n@testable import CADGeometry\n'
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
    command = flags + ['-I', str(source_out), '-emit-executable', '-module-name', 'AngularPhysicalArcPlaneAcceptance',
        *inputs, str(proof), *archives, str(source_out / 'libAngularSourcePhase.a'), '-o', str(product)]
    if args.lane == 'embedded' and '-lc++abi' not in command:
        command += ['-Xlinker', '-lc++abi']
    save('compile-command.json', command)
    recheck()
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
    save('receipt.json', dict(cell='CS-ANGULAR-PHYSICAL-ARC-PLANE-01', lane=args.lane,
        state=state, success=state == 'accepted-selected-current-snapshot', cellComplete=False,
        groups=args.groups.split(','), parentReceipt=str(prior_path), parentSHA256=sha(prior_path),
        retainedSourceContracts=retained_contracts, retainedAuthorityPremises=premise_paths,
        checks=checks, freshProduction=fresh, products=products, runs=runs,
        postHashesMatch=True, rebuiltLowerBodies=0,
        scope='One consistent Revolution retained-source/DI and PublicLiftPlane L5/L6 authority; current exact source and upper bodies.'))
print(state, flush=True)
