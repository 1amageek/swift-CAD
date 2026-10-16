#!/usr/bin/env python3
"""Verify only real CADTopology against exact existing portable Core/Geometry products."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time

SOURCE = Path('/Users/1amageek/.codex/worktrees/g01-direct-delivery-20261016/swift-CAD')
ORIGINAL = Path('/Users/1amageek/.codex/worktrees/m4-m8-completion-recovered/swift-CAD')
HARNESS = ORIGINAL / 'Tests/OriginalQueryExecutionVerification'
sys.path.insert(0, str(HARNESS))
from native_tests import run, RSS_BYTES

PREFIX_HELPER = Path('/Users/1amageek/.codex/verification-artifacts/swift-CAD/u1-direct-callers-20261016/parameters-portable-r1')
sys.path.insert(0, str(PREFIX_HELPER))
from prefix import load_core_geometry_prefix

BIN = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin')
BASE = Path(__file__).resolve().parent
FIXTURE = SOURCE / 'Tests/OriginalQueryExecutionVerification/TopologyDistanceAdmissionPortable.swift'
EXPECTED = [
    'PASS Topology distance public witness and retained result',
    'PASS Topology distance cumulative prefix and exact boundaries',
    'PASS Topology distance zero storage and checkpoints',
    'PASS Topology loop selected nil and independent algebra caps',
    'PASS Topology loop cumulative exact boundaries and cancellation',
    'PASS Topology distance portable all',
]

def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lane', required=True, choices=['asan', 'wasm', 'embedded'])
    parser.add_argument('--core-geometry-receipt', required=True, type=Path)
    parser.add_argument('--native-receipt', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--reuse-topology-module', required=True, type=Path)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--resume-plan', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    record_path = output / 'receipt.json'
    record = None

    def save():
        record_path.write_text(json.dumps(record, indent=2) + '\n')

    def verify_files(files):
        for path, expected in files.items():
            require(digest(path) == expected, 'Pinned input or product changed: ' + path)

    try:
        if args.resume_plan:
            record = json.loads(record_path.read_text())
            require(record['status'] == 'prepared', 'Only an unexecuted immutable plan can resume.')
            require(record['lane'] == args.lane, 'Lane changed.')
            require(record['coreGeometryReceipt']['path'] == str(args.core_geometry_receipt.resolve())
                    and record['nativeReceipt']['path'] == str(args.native_receipt.resolve()), 'Authority selection changed.')
            require(record['runnerSHA256'] == digest(Path(__file__)), 'Driver changed after preparation.')
        else:
            output.mkdir(parents=True, exist_ok=False)
            prefix_path = args.core_geometry_receipt.resolve()
            native_path = args.native_receipt.resolve()
            require(digest(PREFIX_HELPER / 'prefix.py') ==
                '47fb9b75a51dcdd4686add1916ee25bb969bd8b59a0e6efe12887b95ccf734e0',
                'Shared immutable prefix loader changed.')
            accepted = load_core_geometry_prefix(prefix_path, native_path, args.lane, SOURCE)
            native, selected = accepted['native'], accepted['selected']
            sources, products = accepted['sources'], accepted['products']
            files = accepted['files']
            lane = args.lane
            files.update({str(Path(__file__).resolve()): digest(Path(__file__)),
                str(FIXTURE): digest(FIXTURE),
                str(HARNESS / 'native_tests.py'): digest(HARNESS / 'native_tests.py'),
                str(HARNESS / 'typecheck.py'): digest(HARNESS / 'typecheck.py')})
            require(RSS_BYTES == 10 * 1024**3, 'Canonical monitor RSS bound differs.')
            step = native['steps']['CADTopology']
            require(step['exitCode'] == 0 and step.get('stopReason') is None,
                'Native Topology source authority was not accepted.')
            topology = {path: sha for path, sha in native['sourceSHA256'].items()
                if path.startswith('Sources/CADTopology/')}
            actual = {str(path.relative_to(SOURCE)) for path in (SOURCE / 'Sources/CADTopology').rglob('*.swift')}
            require(set(topology) == actual and len(topology) == 142, 'Topology inventory changed.')
            for path, sha in topology.items():
                files[str(SOURCE / path)] = sha
                files[str(native_path.parent / 'snapshot' / path)] = sha
            compile_command = selected['commands']['compile']
            verify_files(files)
            snapshot = output / 'snapshot'
            for relative, sha in topology.items():
                target = snapshot / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(SOURCE / relative, target)
                require(digest(target) == sha, 'Topology copy changed.')
                files[str(target)] = sha
            client = snapshot / FIXTURE.relative_to(SOURCE)
            client.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(FIXTURE, client)
            files[str(client)] = digest(FIXTURE)
            destination = output / lane
            destination.mkdir()
            response = destination / 'TopologySources.rsp'
            response.write_text(''.join('"' + str(snapshot / path) + '"\n' for path in sorted(topology)))
            files[str(response)] = digest(response)
            flags = compile_command[1:compile_command.index('-module-name')] + ['-I', str(destination)]
            module = destination / 'CADTopology.swiftmodule'
            object_file = destination / 'CADTopology.code.o'
            compile_topology = [str(BIN / 'swiftc')] + flags + ['-module-name', 'CADTopology', '-emit-module', '-emit-module-path', str(module)]
            if lane != 'embedded':
                compile_topology += ['-emit-object', '-o', str(object_file)]
            compile_topology += ['@' + str(response)]
            old_link = selected['commands']['link']
            objects = [value for value in old_link if value.endswith('.o')]
            require(not objects if lane == 'embedded' else len(objects) == 4, 'Unexpected library emission model.')
            for path in objects:
                require(path in products, 'Unreceipted link object: ' + path)
            executable = destination / ('TopologyDistance' if lane == 'asan' else 'TopologyDistance.wasm')
            link = [str(BIN / 'swiftc')] + flags + [str(client)]
            if lane != 'embedded':
                link += [str(object_file)] + objects
            link += ['-o', str(executable)] + old_link[old_link.index('-o') + 2:]
            runtime = [str(executable)] if lane == 'asan' else [selected['commands']['runtime'][0], selected['commands']['runtime'][1], str(executable)]
            if lane != 'asan':
                files[runtime[0]] = digest(runtime[0])
                files[runtime[1]] = digest(runtime[1])
            record = {'status': 'prepared', 'scope': 'Actual full CADTopology: public point-distance domain lifecycle and bounded authored polyline loop algebra admission only; no Kernel/IR port or whole-U1 claim.',
                'lane': lane, 'sourceRoot': str(SOURCE), 'sourceCount': {'CADCore': 67, 'CADGeometry': 2170, 'CADTopology': 142},
                'coreGeometryReceipt': {'path': str(prefix_path), 'sha256': digest(prefix_path), 'scope': 'Successful selected lane only; immutable prefix may retain another lane running.'},
                'nativeReceipt': {'path': str(native_path), 'sha256': digest(native_path)},
                'inputAndProductSHA256': files, 'topologySourceSHA256': topology,
                'fixture': {'path': str(FIXTURE), 'sha256': digest(FIXTURE), 'copy': str(client), 'expectedOutputLines': EXPECTED},
                'runnerSHA256': digest(Path(__file__)), 'monitor': {'path': str(HARNESS / 'native_tests.py'), 'sha256': digest(HARNESS / 'native_tests.py'), 'entry': 'run'},
                'commands': {'topology-compile': compile_topology, 'client-link': link, 'runtime': runtime},
                'products': [str(module)] + ([] if lane == 'embedded' else [str(object_file)]), 'executable': str(executable),
                'bounds': {'compileLinkSeconds': 1200, 'runtimeSeconds': 120, 'aggregateRSSBytes': RSS_BYTES, 'ownedCompilerProcesses': 1},
                'steps': {}, 'coreGeometryOrCollectionsRegenerated': False}
            save()
        origin_path = args.reuse_topology_module.resolve()
        origin = json.loads(origin_path.read_text())
        require(origin['lane'] == args.lane and origin['topologySourceSHA256'] == record['topologySourceSHA256']
            and origin['coreGeometryReceipt'] == record['coreGeometryReceipt']
            and origin['nativeReceipt'] == record['nativeReceipt'], 'Module authority changed.')
        require(origin['fixture']['sha256'] == 'b8f96961d7591304a3a098cfe21172d4dca345235d8d459ca6c8b355a64b08ef'
            and record['fixture']['sha256'] == 'cd14d0d38c5b9a42b02ef7549adf868794f4416c20dddfcdf675669191b81865',
            'This reuse is limited to the audited fixture-only key-path correction.')
        previous_fixture = Path(origin['fixture']['copy']).read_text()
        require(previous_fixture.replace('result.map(\\.curve)', 'result.map { $0.curve }') == FIXTURE.read_text(),
            'Fixture changed beyond the single equivalent accessor.')
        require(origin['status'] == 'passed' or (origin['status'] == 'failed'
            and origin['failure'] == 'client-link failed'), 'Origin is not a successful module prefix.')
        step = origin['steps']['topology-compile']
        require(step['exitCode'] == 0 and step.get('stopReason') is None
            and step['command'] == origin['commands']['topology-compile'], 'Original module proof failed.')
        mapped = [value.replace(str(output), str(origin_path.parent))
            for value in record['commands']['topology-compile']]
        require(mapped == origin['commands']['topology-compile'], 'Module command differs beyond private paths.')
        retained = {path: sha for path, sha in origin['inputAndProductSHA256'].items()
            if path != origin['fixture']['path']}
        verify_files(retained)
        require(all(retained[path] == sha for path, sha in origin['compiledProductSHA256'].items()),
            'Compiled module product was not pinned by the successful prefix.')
        old_destination = str(Path(origin['products'][0]).parent)
        destination = str(Path(record['products'][0]).parent)
        record['commands']['client-link'] = [value.replace(destination, old_destination)
            for value in record['commands']['client-link']]
        # Only the actual module search path and linked Topology object use the retained directory.
        record['commands']['client-link'] = [str(output / args.lane / Path(record['executable']).name)
            if value == str(Path(old_destination) / Path(record['executable']).name) else value
            for value in record['commands']['client-link']]
        record['steps']['topology-compile'] = {**step, 'reusedFrom': str(origin_path),
            'reusedReceiptSHA256': digest(origin_path)}
        record['compiledProductSHA256'] = origin['compiledProductSHA256']
        record['products'] = origin['products']
        record['inputAndProductSHA256'].update(retained)
        record['inputAndProductSHA256'][str(origin_path)] = digest(origin_path)
        record['topologyModuleRegenerated'] = False
        record['acceptedModuleOrigin'] = {'path': str(origin_path), 'sha256': digest(origin_path),
            'scope': 'Exact unchanged production, tools and products; fixture-only equivalent accessor correction.'}
        save()
        verify_files(record['inputAndProductSHA256'])
        if args.prepare_only:
            print(json.dumps({'status': 'prepared', 'receipt': str(record_path)}), flush=True)
            return
        environment = dict(os.environ)
        environment.pop('TOOLCHAINS', None)
        environment['PATH'] = str(BIN) + ':' + environment.get('PATH', '')
        environment['ASAN_OPTIONS'] = 'halt_on_error=1:abort_on_error=1'
        record['status'] = 'running'
        deadline = time.monotonic() + 1200
        for name in ['client-link', 'runtime']:
            verify_files(record['inputAndProductSHA256'])
            if name == 'runtime':
                stage_deadline = time.monotonic() + 120
            else:
                stage_deadline = deadline
            result = run(record['commands'][name], output / (name + '.log'), environment,
                deadline=stage_deadline, stage_limit=120 if name == 'runtime' else 1200)
            record['steps'][name] = result
            record['inputAndProductSHA256'][str(output / (name + '.log'))] = result['logSHA256']
            save()
            require(result['exitCode'] == 0 and result['stopReason'] is None, name + ' failed')
            if name == 'topology-compile':
                record['compiledProductSHA256'] = {path: digest(path) for path in record['products']}
                record['inputAndProductSHA256'].update(record['compiledProductSHA256'])
            if name == 'client-link':
                record['executableSHA256'] = digest(record['executable'])
                record['inputAndProductSHA256'][record['executable']] = record['executableSHA256']
            if name == 'runtime':
                lines = (output / 'runtime.log').read_text().splitlines()
                require(all(value in lines for value in EXPECTED), 'Missing actual distance or bounded-loop oracle output.')
            save()
            print(json.dumps({'phase': name, 'exitCode': result['exitCode'], 'elapsedSeconds': result['elapsedSeconds'],
                'peakRSSBytes': result['sampledPeakProcessTreeRSSBytes']}), flush=True)
        verify_files(record['inputAndProductSHA256'])
        record['sourcesProductsAndLogsUnchanged'] = True
        record['status'] = 'passed'
        save()
    except Exception as error:
        if record is not None:
            record['status'] = 'failed'
            record['failure'] = str(error)
            save()
        print(str(error), flush=True)
        raise SystemExit(1)

if __name__ == '__main__':
    main()
