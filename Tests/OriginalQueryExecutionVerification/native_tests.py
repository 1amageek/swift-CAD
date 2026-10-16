#!/usr/bin/env python3
"""Run selected real tests against receipted production modules, never replacement sources.

Example invocation shape (paths are caller-selected):
  native_tests.py --receipt <production-receipt> --through CADGeometry \
      --output <fresh-directory> --test-file <repository-test.swift>
Use --mode typecheck before accepted production objects are available. This mode
checks the same copied test sources with Testing but does not execute any test.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from typecheck import MODULE_ORDER, OPENUSD_MODULES, needs_openusd, tree_hashes, verify_openusd_receipt, verify_collections_products

ROOT = Path(__file__).resolve().parents[2]
SWIFT_BIN = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin')
SDK = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')
TESTING = SWIFT_BIN.parent / 'lib/swift/macosx/testing'
TESTING_PLUGINS = SWIFT_BIN.parent / 'lib/swift/host/plugins/testing'
COLLECTION_RECEIPT = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence/G01-SPHERE-CONE-FINITE-UV/native/products.json'
COLLECTIONS = ['InternalCollectionsUtilities', 'HashTreeCollections']
WALL_SECONDS = 1200
RUNTIME_SECONDS = 120
RSS_BYTES = 10 * 1024**3


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def swift_string(value):
    return json.dumps(str(value), ensure_ascii=False)


def run(command, log_path, env, deadline, stage_limit):
    started = time.monotonic()
    limit = min(stage_limit, deadline - started)
    require(limit > 0, 'The aggregate execution deadline was exhausted.')
    peak = 0
    stopped = None
    tracked = set()
    maximum_processes = 0
    with log_path.open('wb') as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        tracked.add(process.pid)
        while process.poll() is None:
            rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,rss='], text=True)
            rows = [tuple(map(int, row.split())) for row in rows.splitlines()
                    if len(row.split()) == 4]
            tracked.intersection_update(pid for pid, parent, group, rss in rows)
            while True:
                expanded = tracked | {pid for pid, parent, group, rss in rows if parent in tracked}
                if expanded == tracked:
                    break
                tracked = expanded
            live = [(pid, group, rss) for pid, parent, group, rss in rows if pid in tracked]
            rss = sum(rss * 1024 for pid, group, rss in live)
            maximum_processes = max(maximum_processes, len(live))
            peak = max(peak, rss)
            if time.monotonic() - started >= limit or rss > RSS_BYTES:
                stopped = 'wallLimit' if time.monotonic() - started >= limit else 'aggregateRSSLimit'
                groups = {group for pid, group, rss in live} | {process.pid}
                for group in groups:
                    if group != os.getpgrp():
                        try:
                            os.killpg(group, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
                # A detached compiler may ignore TERM after its driver exits.
                # Every observed owned group must stop before the bounded run returns.
                for group in groups:
                    if group != os.getpgrp():
                        try:
                            os.killpg(group, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                break
            time.sleep(0.2)
        code = process.wait()
    return dict(command=command, exitCode=code, elapsedSeconds=time.monotonic() - started,
                sampledPeakProcessTreeRSSBytes=peak, stopReason=stopped,
                rssAccounting='tracked PPID descendants including separate process groups',
                maximumObservedProcessCount=maximum_processes,
                wallLimitSeconds=limit, logSHA256=digest(log_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=ROOT,
                        help='Verify production and test inputs against this checkout; retain runner dependencies here.')
    parser.add_argument('--test-root', type=Path,
                        help='Select real test inputs/resources separately from production sources; defaults to --source-root.')
    parser.add_argument('--dependency-receipt', type=Path,
                        help='Actual pinned OpenUSD SwiftPM receipt; must equal the production receipt dependency.')
    parser.add_argument('--collections-products', type=Path,
                        help='Fresh Collections product map; must equal the production receipt dependency.')
    parser.add_argument('--through', choices=MODULE_ORDER, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--test-file', type=Path, action='append', required=True)
    parser.add_argument('--mode', choices=['test', 'typecheck'], default='test')
    parser.add_argument('--filter', help='Optional SwiftPM test-name regular expression.')
    parser.add_argument('--jobs', type=int, choices=[1, 2], default=2,
                        help='Bound SwiftPM build concurrency within the shared compiler allowance.')
    parser.add_argument('--resume-build', type=Path,
                        help='Reuse a successful, unchanged test build from its private runner receipt.')
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    require(source_root.is_dir(), 'The selected source checkout does not exist.')
    test_root = args.test_root.resolve() if args.test_root else source_root
    require((test_root / 'Tests').is_dir(), 'The selected test checkout does not exist.')
    started = time.monotonic()
    deadline = started + WALL_SECONDS
    output = args.output.resolve()
    require(not output.exists(), 'A fresh private output directory is required: ' + str(output))
    output.mkdir(parents=True)
    record_path = output / 'receipt.json'
    record = dict(mode=args.mode, status='preparing', sourceRoot=str(source_root), wallLimitSeconds=WALL_SECONDS,
                  runtimeLimitSeconds=RUNTIME_SECONDS, aggregateRSSLimitBytes=RSS_BYTES,
                  maximumSwiftPMJobs=args.jobs, steps={}, acceptedProducts={}, testSources={}, testResources={},
                  testRoot=str(test_root))

    def save():
        record['elapsedSeconds'] = time.monotonic() - started
        record_path.write_text(json.dumps(record, indent=2) + '\n')

    def checked_step(name, command, limit):
        step = run(command, output / (name + '.log'), env, deadline, limit)
        record['steps'][name] = step
        save()
        require(step['exitCode'] == 0 and step['stopReason'] is None,
                name + ' failed; inspect ' + str(output / (name + '.log')))

    try:
        env = dict(os.environ)
        env.pop('TOOLCHAINS', None)
        env['PATH'] = str(SWIFT_BIN) + ':/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin'
        env['SWIFT_EXEC'] = str(SWIFT_BIN / 'swiftc')
        env['CC'] = str(SWIFT_BIN / 'clang')
        env['CXX'] = str(SWIFT_BIN / 'clang++')
        env['SDKROOT'] = str(SDK)
        env['LANG'] = 'en_US.UTF-8'
        env['NO_COLOR'] = '1'
        source_receipt = args.receipt.resolve()
        source_bytes = source_receipt.read_bytes()
        production = json.loads(source_bytes)
        require(Path(production.get('sourceRoot', ROOT)).resolve() == source_root,
                'The production receipt belongs to a different source checkout.')
        if production.get('packageManifestSHA256'):
            require(digest(source_root / 'Package.swift') == production['packageManifestSHA256'],
                    'The production package manifest changed.')
        record['productionReceipt'] = str(source_receipt)
        record['productionReceiptSHA256'] = hashlib.sha256(source_bytes).hexdigest()
        require(production['toolchain'] == str(SWIFT_BIN), 'Production toolchain differs from fixed Swift 6.4.0.')
        require(production['sdk'] == str(SDK), 'Production SDK differs from fixed macOS 27.0.')
        require(production['compilerSHA256'] == digest(SWIFT_BIN / 'swiftc'), 'Production compiler hash changed.')
        require(production['sdkSettingsSHA256'] == digest(SDK / 'SDKSettings.json'), 'SDK settings hash changed.')
        checked_step('compiler-version', [str(SWIFT_BIN / 'swiftc'), '--version'], 30)
        version = (output / 'compiler-version.log').read_text()
        require(version == production['compilerVersion'] and 'swift-6.4-RELEASE' in version,
                'Compiler version does not match the accepted production receipt.')
        record['compilerVersion'] = version
        record['toolSHA256'] = {name: digest(SWIFT_BIN / name)
                               for name in ['swift', 'swiftc', 'swift-frontend', 'clang']}
        record['testingMacroSHA256'] = digest(TESTING_PLUGINS / 'libTestingMacros.dylib')
        record['testingInterfaceSHA256'] = digest(TESTING / 'Testing.swiftmodule/arm64-apple-macos.swiftinterface')
        record['sdkSettingsSHA256'] = production['sdkSettingsSHA256']
        record['reusedModuleOrigins'] = {}
        selected = MODULE_ORDER[:MODULE_ORDER.index(args.through) + 1]
        modules = output / 'accepted/modules'
        modules.mkdir(parents=True)
        objects = []
        expected_sources = {}

        def copy_product(source, expected, destination):
            require(source.is_file() and digest(source) == expected, 'Unaccepted product: ' + str(source))
            shutil.copyfile(source, destination)
            require(digest(destination) == expected, 'Copied product hash changed: ' + str(destination))
            record['acceptedProducts'][str(destination)] = dict(source=str(source), sha256=expected)

        external = None
        if any(needs_openusd(name) for name in selected):
            descriptor = production.get('externalDependencyReceipt')
            require(descriptor is not None, 'Upper production modules have no OpenUSD dependency receipt.')
            dependency_path = args.dependency_receipt.resolve() if args.dependency_receipt else Path(descriptor['path'])
            require(digest(dependency_path) == descriptor['sha256'], 'OpenUSD dependency receipt differs from production.')
            external = verify_openusd_receipt(dependency_path, source_root)
            require(external['products'] == descriptor['products']
                    and external['productionResourceBundles'] == descriptor['resourceBundles']
                    and external['productionResourceAccessors'] == descriptor['resourceAccessors'],
                    'OpenUSD dependency products/resources differ from production.')
            record['externalDependencyReceipt'] = descriptor
            dependency_modules = OPENUSD_MODULES if 'CADExchange' in selected else ['OpenUSD']
            for name in dependency_modules:
                product = external['products'][name]
                copy_product(Path(product['module']['path']), product['module']['sha256'], modules / (name + '.swiftmodule'))
                require(digest(source_receipt.parent / 'modules' / (name + '.swiftmodule')) == product['module']['sha256'],
                        'Production imported a different OpenUSD module: ' + name)
                if args.mode == 'test':
                    for index, item in enumerate(product['objects']):
                        destination = modules / 'external' / name / (str(index) + '-' + Path(item['path']).name)
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        copy_product(Path(item['path']), item['sha256'], destination)
                        objects.append(destination)
            for bundle in external['productionResourceBundles']:
                destination = output / 'accepted/resources' / Path(bundle['path']).name
                shutil.copytree(bundle['path'], destination)
                require(tree_hashes(destination) == bundle['files'], 'Copied dependency resource bundle changed.')
                require(tree_hashes(source_receipt.parent / 'resources' / destination.name) == bundle['files'],
                        'Production resource companion differs from dependency receipt.')
            record['externalResourceCopies'] = [dict(path=str(output / 'accepted/resources' / Path(bundle['path']).name),
                                                     files=bundle['files'])
                                                for bundle in external['productionResourceBundles']]

        for name in selected:
            step = production.get('steps', {}).get(name)
            require(step is not None and step['exitCode'] == 0 and step.get('stopReason') is None,
                    'Production module is not accepted: ' + name)
            command = step['command']
            compiled_receipt_path = source_receipt
            compiled_receipt = production
            if step.get('reusedFrom'):
                compiled_receipt_path = Path(step['reusedFrom']).resolve()
                origin_bytes = compiled_receipt_path.read_bytes()
                compiled_receipt = json.loads(origin_bytes)
                origin_step = compiled_receipt.get('steps', {}).get(name)
                require(origin_step is not None and origin_step['exitCode'] == 0
                        and origin_step.get('stopReason') is None and not origin_step.get('reusedFrom'),
                        'Reused module does not identify its original successful compiler receipt: ' + name)
                require(origin_step['command'] == command,
                        'Reused module command differs from the original compiler receipt: ' + name)
                for key in ['toolchain', 'compilerSHA256', 'compilerVersion', 'sdk',
                            'sdkSettingsSHA256', 'reusedProducts']:
                    require(compiled_receipt.get(key) == production.get(key),
                            'Reused module compiler/SDK/dependency premise changed: ' + name + '/' + key)
                if needs_openusd(name):
                    require(compiled_receipt.get('externalDependencyReceipt') == production.get('externalDependencyReceipt'),
                            'Reused upper module OpenUSD premise changed: ' + name)
                for predecessor in selected[:selected.index(name) + 1]:
                    require(compiled_receipt.get('products', {}).get(predecessor)
                            == production.get('products', {}).get(predecessor),
                            'Reused module dependency binary differs from its origin: ' + predecessor)
                    prefix = 'Sources/' + predecessor + '/'
                    origin_inputs = {key: value for key, value in compiled_receipt['sourceSHA256'].items()
                                     if key.startswith(prefix)}
                    current_inputs = {key: value for key, value in production['sourceSHA256'].items()
                                      if key.startswith(prefix)}
                    require(origin_inputs == current_inputs,
                            'Reused module source inputs differ from its origin: ' + predecessor)
                record['reusedModuleOrigins'][name] = dict(receipt=str(compiled_receipt_path),
                    receiptSHA256=hashlib.sha256(origin_bytes).hexdigest())
            require(command[0] == str(SWIFT_BIN / 'swiftc') and '-enable-testing' in command,
                    'Production module lacks the actual fixed/testable compiler contract: ' + name)
            require(command[command.index('-module-name') + 1] == name and '-emit-module' in command,
                    'Production command does not emit the requested module: ' + name)
            require(command[command.index('-target') + 1] == 'arm64-apple-macosx27.0'
                    and command[command.index('-sdk') + 1] == str(SDK), 'Production target mismatch: ' + name)
            require(('-DCAD_EXCHANGE' in command) == (name == 'SwiftCAD'),
                    'CAD_EXCHANGE must match only the actual SwiftCAD target: ' + name)
            declared = {path: value for path, value in production['sourceSHA256'].items()
                        if path.startswith('Sources/' + name + '/')}
            current = {str(path.relative_to(source_root)) for path in (source_root / 'Sources' / name).rglob('*.swift')}
            require(current == set(declared), 'Production source inventory changed: ' + name)
            command_sources = {str(Path(value).resolve()) for value in command if value.endswith('.swift')}
            require(command_sources == {str((compiled_receipt_path.parent / 'snapshot' / path).resolve()) for path in declared},
                    'Production command is not the full receipted source inventory: ' + name)
            for path, expected in declared.items():
                require(digest(source_root / path) == expected, 'Current production source changed: ' + path)
                require(digest(source_receipt.parent / 'snapshot' / path) == expected,
                        'Compiled production snapshot changed: ' + path)
                require(digest(compiled_receipt_path.parent / 'snapshot' / path) == expected,
                        'Original compiler snapshot changed: ' + path)
            expected_sources.update(declared)
            module = Path(command[command.index('-emit-module-path') + 1])
            require(digest(module) == compiled_receipt['products'][name]
                    and compiled_receipt['products'][name] == production['products'][name],
                    'Original compiled module differs from the accepted receipt: ' + name)
            require(digest(compiled_receipt_path.parent / (name + '.log')) == step['logSHA256'],
                    'Original successful compiler log changed: ' + name)
            copy_product(source_receipt.parent / 'modules' / (name + '.swiftmodule'),
                         production['products'][name], modules / (name + '.swiftmodule'))
            if args.mode == 'test':
                require('-emit-object' in command and '-o' in command,
                        'Accepted production object was not emitted: ' + name)
                object_file = Path(command[command.index('-o') + 1])
                require(digest(object_file) == compiled_receipt.get('objects', {})[name]
                        and compiled_receipt['objects'][name] == production.get('objects', {})[name],
                        'Original compiled object differs from the accepted receipt: ' + name)
                destination = modules / (name + '.o')
                copy_product(source_receipt.parent / 'modules' / (name + '.o'),
                             production['objects'][name], destination)
                objects.append(destination)

        collections_descriptor = production.get('collectionsProductsReceipt')
        collections_path = (args.collections_products.resolve() if args.collections_products
                            else Path(collections_descriptor['path']) if collections_descriptor else COLLECTION_RECEIPT)
        collections_bytes = collections_path.read_bytes()
        if collections_descriptor:
            collections, observed = verify_collections_products(collections_path)
            require(observed == collections_descriptor, 'Collections dependency differs from production.')
            record['collectionsProductsReceipt'] = collections_descriptor
        else:
            require(args.collections_products is None, 'Production has no explicit Collections dependency authority.')
            collections = json.loads(collections_bytes)
        record['collectionsReceiptSHA256'] = hashlib.sha256(collections_bytes).hexdigest()
        for name in COLLECTIONS:
            paths = [Path(path) for path in production.get('reusedProducts', {})
                     if Path(path).name == name + '.swiftmodule']
            require(len(paths) == 1, 'Production receipt has no unique Collections module: ' + name)
            source = paths[0]
            expected = production['reusedProducts'][str(source)]
            require(collections.get(str(source)) == expected, 'Collections receipts disagree: ' + name)
            copy_product(source, expected, modules / source.name)
            emitted_modules = source_receipt.parent / 'modules' / source.name
            require(digest(emitted_modules) == expected, 'Production used a different Collections module: ' + name)
            if args.mode == 'test':
                source_object = source.with_suffix('.o')
                destination = modules / source_object.name
                copy_product(source_object, collections[str(source_object)], destination)
                objects.append(destination)

        package = output / 'swift-cad'
        tests = package / 'Tests/FocusedTests'
        tests.mkdir(parents=True)
        copied_tests = []
        for supplied in args.test_file:
            source = supplied.resolve()
            relative = source.relative_to(test_root / 'Tests')
            require(source.suffix == '.swift', 'A real Swift test source is required: ' + str(source))
            destination = tests / relative
            require(not destination.exists(), 'Duplicate test source: ' + str(source))
            destination.parent.mkdir(parents=True, exist_ok=True)
            expected = digest(source)
            shutil.copyfile(source, destination)
            require(digest(destination) == expected, 'Test copy hash mismatch: ' + str(source))
            record['testSources'][str(source)] = dict(copy=str(destination), sha256=expected)
            copied_tests.append(destination)
        resource_targets = {Path(path).relative_to(test_root / 'Tests').parts[0]
                            for path in record['testSources']}
        for target in sorted(resource_targets & {'CADExchangeTests', 'CADUSDImportTests', 'CADKernelTests'}):
            fixture_root = test_root / 'Tests' / target / 'Fixtures'
            require(fixture_root.is_dir(), 'Actual test target Fixtures are missing: ' + target)
            for relative, expected in tree_hashes(fixture_root).items():
                source = fixture_root / relative
                destination = tests / 'Fixtures' / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                require(not destination.exists() or digest(destination) == expected,
                        'Selected test targets have conflicting real resource paths: ' + relative)
                shutil.copyfile(source, destination)
                record['testResources'][str(source)] = dict(copy=str(destination), sha256=expected)
        if 'CADKernelTests' in resource_targets:
            # Kernel fixtures are source-adjacent; share the same hashed resource copy.
            (tests / 'CADKernelTests' / 'Fixtures').symlink_to('../Fixtures', target_is_directory=True)
        def capture_test_resources(build):
            if not record['testResources']:
                return
            accessors = sorted(path for path in build.rglob('resource_bundle_accessor.swift')
                               if path.parent.name == 'DerivedSources' and path.parent.parent.name.startswith('FocusedTests'))
            require(len(accessors) == 1, 'SwiftPM did not generate one real test resource accessor.')
            bundles = sorted(build.rglob('swift-cad_FocusedTests.bundle'))
            require(bundles, 'SwiftPM did not generate a real test Fixtures bundle.')
            for bundle in bundles:
                resource_root = bundle / 'Contents/Resources' if (bundle / 'Contents/Resources').is_dir() else bundle
                for item in record['testResources'].values():
                    relative = Path(item['copy']).relative_to(tests)
                    require(digest(resource_root / relative) == item['sha256'],
                            'SwiftPM bundled Fixtures differ from actual test inputs.')
            record['generatedTestResourceAccessors'] = [dict(path=str(path), sha256=digest(path)) for path in accessors]
            record['testResourceBundles'] = [dict(path=str(path), files=tree_hashes(path)) for path in bundles]

        record['productionSourceSHA256'] = expected_sources
        record['selectedModules'] = selected
        save()
        compiler_flags = ['-I', str(modules), '-package-name', 'swift_cad', '-DNativeExchange']
        if args.through == 'SwiftCAD':
            compiler_flags.append('-DCAD_EXCHANGE')
        linker_flags = [flag for path in objects for flag in ['-Xlinker', str(path)]]
        manifest = '''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "swift-cad", platforms: [.macOS("27.0")], targets: [
    .testTarget(name: "FocusedTests", dependencies: [], RESOURCES
        swiftSettings: [.unsafeFlags(COMPILER_FLAGS)],
        linkerSettings: [.unsafeFlags(LINKER_FLAGS)])
])
'''.replace('COMPILER_FLAGS', '[' + ', '.join(map(swift_string, compiler_flags)) + ']')
        manifest = manifest.replace('LINKER_FLAGS', '[' + ', '.join(map(swift_string, linker_flags)) + ']')
        manifest = manifest.replace('RESOURCES', 'resources: [.copy("Fixtures")],' if record['testResources'] else '')
        (package / 'Package.swift').write_text(manifest)
        record['manifestSHA256'] = digest(package / 'Package.swift')
        if args.mode == 'typecheck':
            if record['testResources']:
                # SwiftPM owns the actual Bundle.module accessor and copied Fixtures.
                # Compiling this real test target emits no test executable and executes no tests.
                command = [str(SWIFT_BIN / 'swift'), 'build', '--package-path', str(package),
                           '--scratch-path', str(output / 'build'), '--jobs', str(args.jobs),
                           '--target', 'FocusedTests', '--triple', 'arm64-apple-macosx27.0',
                           '--sdk', str(SDK), '--disable-index-store', '--verbose']
            else:
                command = [str(SWIFT_BIN / 'swiftc'), '-typecheck', '-parse-as-library',
                           '-whole-module-optimization', '-num-threads', '0',
                           '-swift-version', '6', '-enable-testing', '-package-name', 'swift_cad',
                           '-module-name', 'FocusedTests', '-target', 'arm64-apple-macosx27.0',
                           '-sdk', str(SDK), '-DSWIFT_PACKAGE', '-DDEBUG', '-DNativeExchange',
                           '-I', str(modules), '-I', str(TESTING),
                           '-plugin-path', str(TESTING_PLUGINS)]
                if args.through == 'SwiftCAD':
                    command.append('-DCAD_EXCHANGE')
                command += list(map(str, copied_tests))
            checked_step('test-source-typecheck', command, WALL_SECONDS)
            capture_test_resources(output / 'build')
            record['status'] = 'typecheckedNotExecuted'
        else:
            build = output / 'build'
            if args.resume_build:
                previous_path = args.resume_build.resolve()
                previous_bytes = previous_path.read_bytes()
                previous = json.loads(previous_bytes)
                previous_step = previous['steps']['test-build-and-list']
                require(previous_step['exitCode'] == 0 and previous_step.get('stopReason') is None,
                        'The requested test build was not successful.')
                require(previous['selectedModules'] == selected
                        and previous['productionSourceSHA256'] == expected_sources,
                        'The requested test build has different production inputs.')
                require({path: item['sha256'] for path, item in previous['testSources'].items()}
                        == {path: item['sha256'] for path, item in record['testSources'].items()},
                        'The requested test build has different test inputs.')
                require({path: item['sha256'] for path, item in previous.get('testResources', {}).items()}
                        == {path: item['sha256'] for path, item in record['testResources'].items()},
                        'The requested test build has different resource inputs.')
                require(previous.get('externalDependencyReceipt') == record.get('externalDependencyReceipt'),
                        'The requested test build has different OpenUSD dependency inputs.')
                previous_products = previous['acceptedProducts']
                require({Path(path).name: item['sha256'] for path, item in previous_products.items()}
                        == {Path(path).name: item['sha256'] for path, item in record['acceptedProducts'].items()},
                        'The requested test build used different module/object products.')
                require(all(digest(Path(path)) == item['sha256'] for path, item in previous_products.items()),
                        'The requested test build products changed.')
                require(all(digest(Path(item['copy'])) == item['sha256']
                            for item in previous['testSources'].values()), 'The requested test copies changed.')
                command = previous_step['command']
                package = Path(command[command.index('--package-path') + 1])
                build = Path(command[command.index('--scratch-path') + 1])
                require(command[0:2] == [str(SWIFT_BIN / 'swift'), 'test'] and command[-1] == 'list'
                        and command[command.index('--sdk') + 1] == str(SDK)
                        and command[command.index('--triple') + 1] == 'arm64-apple-macosx27.0',
                        'The requested test build used a different command contract.')
                require(digest(package / 'Package.swift') == previous['manifestSHA256'],
                        'The requested test build manifest changed.')
                require(digest(previous_path.parent / 'test-build-and-list.log') == previous_step['logSHA256'],
                        'The requested successful build log changed.')
                record['resumedBuild'] = dict(receipt=str(previous_path),
                    receiptSHA256=hashlib.sha256(previous_bytes).hexdigest(),
                    manifest=str(package / 'Package.swift'), manifestSHA256=previous['manifestSHA256'],
                    products=previous_products, testSources=previous['testSources'],
                    testResources=previous.get('testResources', {}))
                record['steps']['test-build-and-list'] = dict(previous_step, reusedFrom=str(previous_path))
            common = [str(SWIFT_BIN / 'swift'), 'test', '--package-path', str(package),
                      '--scratch-path', str(build), '--jobs', str(args.jobs),
                      '--triple', 'arm64-apple-macosx27.0', '--sdk', str(SDK),
                      '-Xswiftc', '-I', '-Xswiftc', str(modules),
                      '--enable-swift-testing', '--disable-xctest', '--disable-index-store', '--verbose']
            if not args.resume_build:
                checked_step('test-build-and-list', common + ['list'], WALL_SECONDS)
            capture_test_resources(build)
            linked = set()
            for bundle in build.rglob('*.xctest'):
                metadata = bundle / 'Contents/Info.plist'
                if not metadata.is_file():
                    continue
                with metadata.open('rb') as source:
                    executable_name = plistlib.load(source)['CFBundleExecutable']
                executable = bundle / 'Contents/MacOS' / executable_name
                require(executable.is_file() and os.access(executable, os.X_OK),
                        'SwiftPM test bundle has no executable: ' + str(bundle))
                linked.add(executable.resolve())
            linked = sorted(linked)
            require(len(linked) == 1, 'SwiftPM did not produce one discoverable test executable.')
            record['testExecutable'] = dict(path=str(linked[0]), sha256=digest(linked[0]))
            if external:
                for bundle in external['productionResourceBundles']:
                    # Keep companions beside the executable and SwiftPM build products.
                    # The immutable original absolute fallback is also verified below.
                    for parent in {linked[0].parent, linked[0].parents[3]}:
                        destination = parent / Path(bundle['path']).name
                        if not destination.exists():
                            shutil.copytree(bundle['path'], destination)
                        require(tree_hashes(destination) == bundle['files'], 'Runtime resource companion differs.')
                        record['externalResourceCopies'].append(dict(path=str(destination), files=bundle['files']))
            report = output / 'results.xml'
            command = common + ['--skip-build', '--xunit-output', str(report)]
            if args.filter:
                command += ['--filter', args.filter]
            checked_step('test-runtime', command, RUNTIME_SECONDS)
            require(report.is_file(), 'SwiftPM returned no actual test result report.')
            result = ET.parse(report).getroot()
            cases = list(result.iter('testcase'))
            require(cases and not list(result.iter('failure')) and not list(result.iter('error')),
                    'The actual run executed no tests or reported test failures.')
            record['executedTestCases'] = len(cases)
            record['testReportSHA256'] = digest(report)
            record['status'] = 'passed'
        if collections_descriptor:
            require(verify_collections_products(collections_path)[1] == collections_descriptor,
                    'Collections dependency changed during verification.')
        if external:
            verify_openusd_receipt(dependency_path, source_root)
            require(all(tree_hashes(Path(item['path'])) == item['files']
                        for item in record['externalResourceCopies']), 'Runtime resource companions changed.')
        require(all(digest(Path(path)) == item['sha256'] and digest(Path(item['copy'])) == item['sha256']
                    for path, item in record['testResources'].items()), 'Real test Fixtures changed during verification.')
        require(all(digest(source_root / path) == expected for path, expected in expected_sources.items()),
                'Production source premise changed during focused verification.')
        require(all(digest(Path(path)) == item['sha256'] and digest(Path(item['copy'])) == item['sha256']
                    for path, item in record['testSources'].items()), 'Test source changed during verification.')
        require(all(digest(Path(path)) == item['sha256'] for path, item in record['acceptedProducts'].items()),
                'A frozen accepted product changed during verification.')
        if record.get('resumedBuild'):
            previous = record['resumedBuild']
            require(all(digest(Path(item['copy'])) == item['sha256'] for item in previous['testResources'].values()),
                    'The reused build real Fixtures changed.')
            require(digest(Path(previous['manifest'])) == previous['manifestSHA256']
                    and all(digest(Path(path)) == item['sha256'] for path, item in previous['products'].items())
                    and all(digest(Path(item['copy'])) == item['sha256'] for item in previous['testSources'].values()),
                    'The reused test build premises changed during verification.')
        if record.get('testExecutable'):
            require(digest(Path(record['testExecutable']['path'])) == record['testExecutable']['sha256'],
                    'The linked test executable changed during verification.')
        require(all(digest(Path(item['path'])) == item['sha256']
                    for item in record.get('generatedTestResourceAccessors', [])),
                'SwiftPM generated test resource accessor changed.')
        require(all(tree_hashes(Path(item['path'])) == item['files']
                    for item in record.get('testResourceBundles', [])), 'SwiftPM test Fixtures bundle changed.')
        if production.get('packageManifestSHA256'):
            require(digest(source_root / 'Package.swift') == production['packageManifestSHA256'],
                    'Production package manifest changed during verification.')
        record['sourcesAndProductsUnchanged'] = True
        require(time.monotonic() <= deadline, 'Aggregate execution exceeded its deadline.')
        save()
        print(json.dumps(dict(status=record['status'], receipt=str(record_path),
                              executedTestCases=record.get('executedTestCases', 0))))
        return 0
    except Exception as error:
        record['status'] = 'failed'
        record['failure'] = str(error)
        record['productionSourceDrift'] = [path for path, expected in record.get('productionSourceSHA256', {}).items()
            if not (source_root / path).is_file() or digest(source_root / path) != expected]
        record['testSourceDrift'] = [path for path, item in record['testSources'].items()
            if not Path(path).is_file() or digest(Path(path)) != item['sha256']
            or not Path(item['copy']).is_file() or digest(Path(item['copy'])) != item['sha256']]
        record['acceptedProductDrift'] = [path for path, item in record['acceptedProducts'].items()
            if not Path(path).is_file() or digest(Path(path)) != item['sha256']]
        save()
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
