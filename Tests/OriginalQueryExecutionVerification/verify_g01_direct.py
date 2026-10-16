#!/usr/bin/env python3
"""Compile the public G01 CLI fixture against accepted production objects only."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / 'Tests/OriginalQueryExecutionVerification/native_tests.py'
spec = importlib.util.spec_from_file_location('g01_native_limits', SHARED)
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
h = common.digest
need = common.require

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=ROOT,
                        help='Validate production inputs in this checkout; retain original fixture and artifact origins.')
    parser.add_argument('--collections-products', type=Path,
                        help='Fresh Collections map; must match the accepted production dependency.')
    parser.add_argument('--groups', nargs='+', choices=['ordinary', 'admitted', 'prepared', 'readers', 'resources', 'full', 'all'], default=['all'])
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    need(source_root.is_dir(), 'Production source root does not exist.')
    started = time.monotonic()
    deadline = started + 1200
    out = args.output.resolve()
    need(not out.exists(), 'Fresh output directory required.')
    out.mkdir(parents=True)
    record = {'status': 'preparing', 'scope': 'actual production public SSI only', 'steps': {},
        'acceptedProducts': {}, 'sourceSHA256': {}, 'runtimeLimitSeconds': 120,
        'compilerLimitSeconds': 1200, 'aggregateRSSLimitBytes': 10 * 1024**3,
        'sharedBoundedRunner': str(SHARED), 'sharedBoundedRunnerSHA256': h(SHARED),
        'sourceRoot': str(source_root)}
    def save():
        record['elapsedSeconds'] = time.monotonic() - started
        (out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    def step(name, command, limit):
        value = common.run(command, out / (name + '.log'), env, deadline, limit)
        record['steps'][name] = value
        save()
        need(value['exitCode'] == 0 and value['stopReason'] is None, name + ' failed.')
    def product(source, expected, destination):
        need(source.is_file() and h(source) == expected, 'Unaccepted production product: ' + str(source))
        shutil.copyfile(source, destination)
        need(h(destination) == expected, 'Product copy changed.')
        record['acceptedProducts'][str(destination)] = {'source': str(source), 'sha256': expected}
    try:
        receipt = args.receipt.resolve()
        production = json.loads(receipt.read_text())
        need(Path(production.get('sourceRoot', ROOT)).resolve() == source_root,
             'Production receipt belongs to a different source checkout.')
        inputs = ROOT / 'Tests/OriginalPublicAcceptanceVerification/G01Direct/inputs.json'
        contract = json.loads(inputs.read_text())
        record.update(productionReceipt=str(receipt), productionReceiptSHA256=h(receipt),
            fixtureInputReceipt=str(inputs), fixtureInputReceiptSHA256=h(inputs))
        tool = common.SWIFT_BIN
        sdk = common.SDK
        need(production['toolchain'] == str(tool) and production['sdk'] == str(sdk), 'Fixed toolchain/SDK mismatch.')
        need(h(tool / 'swiftc') == production['compilerSHA256'], 'Compiler changed.')
        need(h(sdk / 'SDKSettings.json') == production['sdkSettingsSHA256'], 'SDK settings changed.')
        env = dict(os.environ)
        env.pop('TOOLCHAINS', None)
        env.update(PATH=str(tool) + ':/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin',
            SWIFT_EXEC=str(tool / 'swiftc'), CC=str(tool / 'clang'), CXX=str(tool / 'clang++'), SDKROOT=str(sdk))
        step('compiler-version', [str(tool / 'swiftc'), '--version'], 30)
        need((out / 'compiler-version.log').read_text() == production['compilerVersion'], 'Compiler identity mismatch.')
        modules = out / 'accepted/modules'
        modules.mkdir(parents=True)
        objects = []
        record['originalModuleReceipts'] = {}
        for name in ['CADCore', 'CADGeometry']:
            accepted = production.get('steps', {}).get(name, {})
            need(accepted.get('exitCode') == 0 and accepted.get('stopReason') is None, 'Module not accepted: ' + name)
            command = accepted['command']
            origin_path = Path(accepted.get('reusedFrom', receipt)).resolve()
            origin = json.loads(origin_path.read_text())
            original = origin['steps'][name]
            need(original['exitCode'] == 0 and original.get('stopReason') is None
                and not original.get('reusedFrom') and original['command'] == command, 'Unverified original compiler invocation.')
            for key in ['toolchain', 'compilerSHA256', 'compilerVersion', 'sdk', 'sdkSettingsSHA256', 'reusedProducts']:
                need(origin.get(key) == production.get(key), 'Reused binary premise mismatch: ' + key)
            need(command[0] == str(tool / 'swiftc') and '-emit-module' in command and '-emit-object' in command
                and command[command.index('-target') + 1] == 'arm64-apple-macosx27.0'
                and command[command.index('-sdk') + 1] == str(sdk), 'Module target/object command mismatch.')
            declared = {p: v for p, v in production['sourceSHA256'].items() if p.startswith('Sources/' + name + '/')}
            original_sources = {p: v for p, v in origin['sourceSHA256'].items() if p.startswith('Sources/' + name + '/')}
            current = {str(p.relative_to(source_root)) for p in (source_root / 'Sources' / name).rglob('*.swift')}
            need(current == set(declared) and declared == original_sources, 'Production source inventory differs.')
            actual_inputs = {str(Path(p).resolve()) for p in command if p.endswith('.swift')}
            need(actual_inputs == {str((origin_path.parent / 'snapshot' / p).resolve()) for p in declared}, 'Compiler input inventory differs.')
            for p, expected in declared.items():
                need(h(source_root / p) == expected and h(receipt.parent / 'snapshot' / p) == expected
                    and h(origin_path.parent / 'snapshot' / p) == expected, 'Source premise changed: ' + p)
            record['sourceSHA256'].update(declared)
            need(h(origin_path.parent / (name + '.log')) == accepted['logSHA256'], 'Original successful compiler log changed.')
            need(origin['products'][name] == production['products'][name]
                and origin['objects'][name] == production['objects'][name], 'Product differs from original compiler receipt.')
            need(h(Path(command[command.index('-emit-module-path') + 1])) == production['products'][name]
                and h(Path(command[command.index('-o') + 1])) == production['objects'][name], 'Original compiler outputs changed.')
            product(receipt.parent / 'modules' / (name + '.swiftmodule'), production['products'][name], modules / (name + '.swiftmodule'))
            destination = modules / (name + '.o')
            product(receipt.parent / 'modules' / (name + '.o'), production['objects'][name], destination)
            objects.append(destination)
            record['originalModuleReceipts'][name] = {'path': str(origin_path), 'sha256': h(origin_path), 'compilerLogSHA256': accepted['logSHA256']}
        collections_descriptor = production.get('collectionsProductsReceipt')
        collection_path = (args.collections_products.resolve() if args.collections_products
                           else Path(collections_descriptor['path']) if collections_descriptor else common.COLLECTION_RECEIPT)
        if collections_descriptor:
            collections, observed = common.verify_collections_products(collection_path)
            need(observed == collections_descriptor, 'Collections dependency differs from production.')
            record['collectionsProductsReceipt'] = collections_descriptor
        else:
            need(args.collections_products is None, 'Production has no explicit Collections dependency authority.')
            collections = json.loads(collection_path.read_text())
        record['collectionsReceiptSHA256'] = h(collection_path)
        for name in common.COLLECTIONS:
            paths = [Path(p) for p in production['reusedProducts'] if Path(p).name == name + '.swiftmodule']
            need(len(paths) == 1, 'Ambiguous Collections module.')
            source = paths[0]
            need(collections.get(str(source)) == production['reusedProducts'][str(source)], 'Collections provenance differs.')
            product(source, collections[str(source)], modules / source.name)
            need(h(receipt.parent / 'modules' / source.name) == collections[str(source)], 'Production Collections input changed.')
            source_object = source.with_suffix('.o')
            destination = modules / source_object.name
            product(source_object, collections[str(source_object)], destination)
            objects.append(destination)
        fixture = ROOT / contract['fixture']
        need(h(fixture) == contract['fixtureSHA256'], 'Frozen fixture changed.')
        copied = out / fixture.name
        shutil.copyfile(fixture, copied)
        record['fixture'] = {'source': str(fixture), 'copy': str(copied), 'sha256': h(fixture)}
        executable = out / 'G01DirectAcceptance'
        command = [str(tool / 'swiftc'), '-parse-as-library', '-swift-version', '6', '-O',
            '-whole-module-optimization', '-tools-directory', str(tool), '-Xclang-linker',
            '-fuse-ld=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld',
            '-package-name', 'swift_cad', '-target', 'arm64-apple-macosx27.0', '-sdk', str(sdk),
            '-I', str(modules), str(copied), *map(str, objects), '-o', str(executable)]
        step('fixture-compile-link', command, 1200)
        record['executableSHA256'] = h(executable)
        for group in args.groups:
            step('runtime-' + group, [str(executable), group], 120)
            lines = (out / ('runtime-' + group + '.log')).read_text().splitlines()
            expected = contract['expectedOutput'] if group == 'all' else ['PASS G01 public ' + group]
            need(all(value in lines for value in expected), 'Missing actual PASS group outputs.')
        need(all(h(source_root / p) == expected for p, expected in record['sourceSHA256'].items()), 'Production source drift.')
        need(all(h(Path(p)) == item['sha256'] and h(Path(item['source'])) == item['sha256']
            for p, item in record['acceptedProducts'].items()), 'Production product drift.')
        if collections_descriptor:
            need(common.verify_collections_products(collection_path)[1] == collections_descriptor,
                 'Collections dependency changed during public verification.')
        need(h(fixture) == record['fixture']['sha256'] and h(copied) == record['fixture']['sha256'], 'Fixture source drift.')
        need(h(inputs) == record['fixtureInputReceiptSHA256'] and h(SHARED) == record['sharedBoundedRunnerSHA256'], 'Runner premise drift.')
        record['status'] = 'passed'
        record['sourcesAndProductsUnchanged'] = True
        save()
        print(json.dumps({'status': record['status'], 'receipt': str(out / 'receipt.json')}))
        return 0
    except Exception as error:
        record['status'] = 'failed'
        record['failure'] = str(error)
        save()
        print(str(error), file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
