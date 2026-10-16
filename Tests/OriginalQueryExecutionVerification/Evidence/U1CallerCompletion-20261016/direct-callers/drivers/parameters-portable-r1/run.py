#!/usr/bin/env python3
"""Verify the real expression witness using only Parameter.swift and its two Modeling owners."""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import time

from prefix import BIN, digest, require, verify_files, load_core_geometry_prefix

SOURCE = Path('/Users/1amageek/.codex/worktrees/g01-direct-delivery-20261016/swift-CAD')
ORIGINAL = Path('/Users/1amageek/.codex/worktrees/m4-m8-completion-recovered/swift-CAD')
HARNESS = ORIGINAL / 'Tests/OriginalQueryExecutionVerification'
sys.path.insert(0, str(HARNESS))
from native_tests import run, RSS_BYTES

FIXTURE = SOURCE / 'Tests/OriginalQueryExecutionVerification/ParameterExpressionAdmissionPortable.swift'
SOURCES = {'CADIR': ['Sources/CADIR/Parameter.swift'], 'CADModeling': [
    'Sources/CADModeling/ParameterResolving.swift', 'Sources/CADModeling/ParameterResolver.swift']}
EXPECTED = [
    'PASS parameter actual existential all13 expression laws',
    'PASS parameter four Core continuation laws and ordinary parity',
    'PASS parameter returned quantity lifetime',
    'PASS parameter cumulative same caller work and bytes',
    'PASS parameter exact N N-minus-1 work storage and bytes0',
    'PASS parameter independent value depth source0 geometry0 coefficient0',
    'PASS parameter original units domain variable and left-before-right errors',
    'PASS parameter entry inner numeric and terminal cancellation',
    'PASS parameter portable all',
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lane', required=True, choices=['asan', 'wasm', 'embedded'])
    parser.add_argument('--core-geometry-receipt', required=True, type=Path)
    parser.add_argument('--native-receipt', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--resume-plan', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    record_path = output / 'receipt.json'
    record = None

    def save():
        record_path.write_text(json.dumps(record, indent=2) + '\n')

    try:
        if args.resume_plan:
            record = json.loads(record_path.read_text())
            require(record['status'] == 'prepared', 'Only an unexecuted immutable plan can resume.')
            require(record['lane'] == args.lane, 'Selected lane changed.')
            require(record['coreGeometryReceipt']['path'] == str(args.core_geometry_receipt.resolve()) and
                record['nativeReceipt']['path'] == str(args.native_receipt.resolve()), 'Selected authorities changed.')
        else:
            output.mkdir(parents=True, exist_ok=False)
            prefix = load_core_geometry_prefix(args.core_geometry_receipt, args.native_receipt, args.lane, SOURCE)
            files = prefix['files']
            files[str(Path(__file__).resolve())] = digest(Path(__file__))
            files[str(FIXTURE)] = digest(FIXTURE)
            for name in ['native_tests.py', 'typecheck.py']:
                files[str(HARNESS / name)] = digest(HARNESS / name)
            require(RSS_BYTES == 10 * 1024**3, 'Canonical monitor RSS bound differs.')
            source_hashes = {}
            for module, relative_paths in SOURCES.items():
                native_step = prefix['native']['steps'][module]
                require(native_step['exitCode'] == 0 and native_step.get('stopReason') is None, 'Native whole module binding was not accepted: ' + module)
                for relative in relative_paths:
                    sha = prefix['native']['sourceSHA256'][relative]
                    source_hashes[relative] = sha
                    files[str(SOURCE / relative)] = sha
                    files[str(args.native_receipt.resolve().parent / 'snapshot' / relative)] = sha
            verify_files(files)
            snapshot = output / 'snapshot'
            for relative, sha in {**source_hashes, str(FIXTURE.relative_to(SOURCE)): digest(FIXTURE)}.items():
                target = snapshot / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(SOURCE / relative, target)
                require(digest(target) == sha, 'Actual source snapshot changed: ' + relative)
                files[str(target)] = sha
            destination = output / args.lane
            destination.mkdir()
            flags = prefix['flags'] + ['-I', str(destination)]
            commands = {}
            products = {}
            objects = []
            for module, relative_paths in SOURCES.items():
                response = destination / (module + 'Sources.rsp')
                response.write_text(''.join('"' + str(snapshot / relative) + '"\n' for relative in relative_paths))
                files[str(response)] = digest(response)
                module_path = destination / (module + '.swiftmodule')
                object_path = destination / (module + '.code.o')
                command = [str(BIN / 'swiftc')] + flags + ['-module-name', module, '-emit-module', '-emit-module-path', str(module_path)]
                products[module] = [str(module_path)]
                if args.lane != 'embedded':
                    command += ['-emit-object', '-o', str(object_path)]
                    products[module].append(str(object_path))
                    objects.append(str(object_path))
                commands[module + '-compile'] = command + ['@' + str(response)]
            client = snapshot / FIXTURE.relative_to(SOURCE)
            executable = destination / ('ParameterExpression' if args.lane == 'asan' else 'ParameterExpression.wasm')
            commands['client-link'] = [str(BIN / 'swiftc')] + flags + [str(client)] + objects + prefix['objects'] + ['-o', str(executable)] + prefix['linkTail']
            commands['runtime'] = prefix['runtimePrefix'] + [str(executable)]
            record = {'status': 'prepared', 'scope': 'Finite actual CADIR Parameter.swift and CADModeling ParameterResolving/ParameterResolver expression witness only. Full Native module binding authority retained; no whole portable IR/Modeling/table/Kernel claim.',
                'sourceRoot': str(SOURCE), 'lane': args.lane,
                'sourceCount': {'CADCore': 67, 'CADGeometry': 2170, 'CADIR': 1, 'CADModeling': 2},
                'coreGeometryReceipt': prefix['receipt'], 'nativeReceipt': prefix['nativeReceipt'],
                'sourceSHA256': source_hashes, 'inputAndProductSHA256': files,
                'fixture': {'path': str(FIXTURE), 'copy': str(client), 'sha256': digest(FIXTURE), 'expectedOutputLines': EXPECTED},
                'monitor': {'path': str(HARNESS / 'native_tests.py'), 'sha256': digest(HARNESS / 'native_tests.py'), 'entry': 'run'},
                'sharedPrefixLoader': {'path': str(Path(__file__).resolve().parent / 'prefix.py'), 'sha256': digest(Path(__file__).resolve().parent / 'prefix.py')},
                'commands': commands, 'products': products, 'executable': str(executable),
                'bounds': {'compileLinkSeconds': 1200, 'runtimeSeconds': 120, 'aggregateRSSBytes': RSS_BYTES, 'ownedCompilerProcesses': 1},
                'coreGeometryOrCollectionsRegenerated': False, 'steps': {}}
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
        for name in ['CADIR-compile', 'CADModeling-compile', 'client-link', 'runtime']:
            verify_files(record['inputAndProductSHA256'])
            result = run(record['commands'][name], output / (name + '.log'), environment,
                deadline=time.monotonic() + 120 if name == 'runtime' else deadline,
                stage_limit=120 if name == 'runtime' else 1200)
            record['steps'][name] = result
            record['inputAndProductSHA256'][str(output / (name + '.log'))] = result['logSHA256']
            save()
            require(result['exitCode'] == 0 and result['stopReason'] is None, name + ' failed')
            if name.endswith('-compile'):
                module = name.removesuffix('-compile')
                hashes = {path: digest(path) for path in record['products'][module]}
                record.setdefault('compiledProductSHA256', {}).update(hashes)
                record['inputAndProductSHA256'].update(hashes)
            elif name == 'client-link':
                record['executableSHA256'] = digest(record['executable'])
                record['inputAndProductSHA256'][record['executable']] = record['executableSHA256']
            else:
                lines = (output / 'runtime.log').read_text().splitlines()
                require(all(value in lines for value in EXPECTED), 'Missing actual expression oracle output.')
                record['matchedOracleLines'] = [value for value in EXPECTED if value in lines]
            save()
            print(json.dumps({'phase': name, 'exitCode': result['exitCode'], 'elapsedSeconds': result['elapsedSeconds'], 'peakRSSBytes': result['sampledPeakProcessTreeRSSBytes']}), flush=True)
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
