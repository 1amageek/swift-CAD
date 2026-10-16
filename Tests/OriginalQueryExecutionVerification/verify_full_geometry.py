#!/usr/bin/env python3
"""Pin complete real Core/Geometry and run bounded portable public oracles."""
import argparse
import json
import os
import shlex
from pathlib import Path
import shutil
import time
from verify_lineage import ROOT, HERE, BIN, SWIFTC, SDKBASE, MACSDK, LD, RSS_LIMIT, COMPILE_SECONDS, RUNTIME_SECONDS, digest
from native_tests import run as run_bounded_process, RSS_BYTES as BOUNDED_RSS_BYTES

NATIVE = ROOT / '.build/u1-semantic-native-20261015-r19/receipt.json'
LINEAGE = HERE / 'Evidence/LineageCanonical-20261015-r2/receipt.json'
ASAN_LINEAGE = HERE / 'Evidence/LineageCanonical-20261015/receipt.json'
PRODUCT_RECEIPTS = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence/G01-SPHERE-CONE-FINITE-UV'
EMBEDDED_LIBRARY_MODEL = HERE / 'Evidence/EmbeddedSwiftLibraries-20261015.json'
EMBEDDED_LIBRARY_MODEL_SHA256 = 'd5ee66765a73cf3426740e9a19c1e09ef9ff710bc62bf97c8f60fc26e057550b'
G01_RUNTIME_GROUPS = ['ordinary', 'admitted', 'prepared', 'readers', 'resources', 'full', 'all']


def runtime_steps(lane, command, groups, expected):
    """Use the existing G01 CLI groups for Native and normal WASM clients."""
    if lane in ['asan', 'wasm'] and groups:
        assert len(groups) == len(set(groups)), 'Duplicate runtime groups do not add evidence'
        return [{'phase': 'runtime-' + group, 'command': command + [group],
            'requiredOutputLines': expected if group == 'all' else ['PASS G01 public ' + group]}
            for group in groups]
    return [{'phase': 'runtime', 'command': command, 'requiredOutputLines': expected}]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--source-receipt', type=Path, default=NATIVE,
        help='Root-owned frozen source hash manifest; defaults to the historical Native r19 receipt.')
    parser.add_argument('--source-root', type=Path, default=ROOT,
        help='Production source root named by the input authority; harness and fixture stay at their original root.')
    parser.add_argument('--compile-core', action='store_true',
        help='Compile all authoritative Core sources instead of reusing a different Core source snapshot.')
    parser.add_argument('--reuse-core-products', type=Path,
        help='Reuse only a successful exact Core source prefix; Geometry still compiles freshly.')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--resume-plan', action='store_true')
    parser.add_argument('--compile-only', action='store_true')
    parser.add_argument('--reuse-geometry-products', type=Path)
    parser.add_argument('--fixture', type=Path, default=HERE / 'FullGeometryPortable.swift')
    parser.add_argument('--fixture-root', type=Path, default=ROOT,
        help='Root containing the explicitly selected real Tests fixture; other harness evidence stays canonical.')
    parser.add_argument('--expected-output', action='append',
        help='Exact required runtime line; repeat for each root-owned public-query oracle.')
    parser.add_argument('--runtime-group', action='append', choices=G01_RUNTIME_GROUPS,
        help='Existing G01 CLI group for ASAN and normal WASM; Embedded runs all oracles together. Each group retains its separate 120-second runtime bound.')
    parser.add_argument('--lanes', nargs='+', choices=['asan', 'wasm', 'embedded'], default=['wasm', 'embedded'])
    args = parser.parse_args()
    assert not (args.compile_core and args.reuse_core_products), 'Select fresh Core compilation or exact Core reuse'
    output = Path(args.output).resolve()
    environment = dict(os.environ)
    environment['PATH'] = str(BIN) + ':' + environment.get('PATH', '')
    environment.pop('TOOLCHAINS', None)
    environment['ASAN_OPTIONS'] = 'halt_on_error=1:abort_on_error=1'
    os.chdir(ROOT)
    if not args.resume_plan:
        output.mkdir(parents=True, exist_ok=False)
        source_receipt = args.source_receipt.resolve()
        source_root = args.source_root.resolve()
        native = json.loads(source_receipt.read_text())
        assert digest(EMBEDDED_LIBRARY_MODEL) == EMBEDDED_LIBRARY_MODEL_SHA256
        shutil.copyfile(source_receipt, output / 'RootSourceReceipt.json')
        lineage = json.loads(LINEAGE.read_text())
        asan_lineage = json.loads(ASAN_LINEAGE.read_text())
        assert lineage['toolSHA256'] == asan_lineage['toolSHA256']
        assert all(digest(BIN / name) == h for name, h in lineage['toolSHA256'].items())
        assert all(digest(SDKBASE / name) == h for name, h in lineage['wasmSDK']['metadataSHA256'].items())
        assert digest(MACSDK / 'SDKSettings.json') == asan_lineage['nativeSDK']['SDKSettings.json']
        assert digest(LD) == asan_lineage['nativeLinker']['sha256']
        core = {p: h for p, h in native['sourceSHA256'].items() if p.startswith('Sources/CADCore/')}
        geometry = {p: h for p, h in native['sourceSHA256'].items() if p.startswith('Sources/CADGeometry/')}
        reused_core = None
        if args.reuse_core_products:
            core_receipt = args.reuse_core_products.resolve() / 'receipt.json'
            reused_core = json.loads(core_receipt.read_text())
            assert reused_core['status'] == 'passed', 'Core reuse requires an accepted receipt'
            assert core == {p: h for p, h in reused_core['sourceSHA256'].items() if p.startswith('Sources/CADCore/')}, 'Core reuse source inventory differs'
            assert reused_core['toolSHA256'] == lineage['toolSHA256']
            assert reused_core['wasmSDK'] == lineage['wasmSDK']
            assert reused_core['nativeSDK'] == asan_lineage['nativeSDK']
            assert reused_core['nativeLinker'] == asan_lineage['nativeLinker']
            for relative, expected in core.items():
                assert digest(args.reuse_core_products.resolve() / 'snapshot' / relative) == expected, 'Retained Core source changed: ' + relative
            shutil.copyfile(core_receipt, output / 'CoreReuseReceipt.json')
        if not args.compile_core and not reused_core:
            assert core == lineage['sourceSHA256']
            assert core == asan_lineage['sourceSHA256']
        assert all(digest(source_root / p) == h for p, h in {**core, **geometry}.items())
        actual_core = {str(p.relative_to(source_root)) for p in (source_root / 'Sources/CADCore').rglob('*.swift')}
        assert actual_core == set(core)
        actual = {str(p.relative_to(source_root)) for p in (source_root / 'Sources/CADGeometry').rglob('*.swift')}
        assert actual == set(geometry)
        # The extra Native build defines do not select any Core declarations.
        core_conditionals = {p: [line for line in (source_root / p).read_text().splitlines() if '#if' in line or '#elseif' in line] for p in core}
        if not args.compile_core and not reused_core:
            assert not any(any(word in line for word in ['DEBUG', 'NativeExchange', 'SWIFT_PACKAGE']) for lines in core_conditionals.values() for line in lines)
        inputs = {**core, **geometry}
        input_origins = {p: str(source_root / p) for p in inputs}
        fixture_root = args.fixture_root.resolve()
        assert fixture_root.is_dir(), 'The selected fixture root does not exist'
        fixture_source = args.fixture.resolve()
        fixture_relative = fixture_source.relative_to(fixture_root)
        assert fixture_relative.parts and fixture_relative.parts[0] == 'Tests', 'The fixture must belong to the selected root Tests tree'
        expected_output = args.expected_output or ['PASS full Geometry portable: 5 oracle groups']
        assert args.expected_output or fixture_source == (HERE / 'FullGeometryPortable.swift').resolve(), 'Supply exact root-owned oracle lines for an alternate fixture'
        if args.runtime_group:
            assert any(lane in ['asan', 'wasm'] for lane in args.lanes) and fixture_source.name == 'G01DirectAcceptance.swift', 'Runtime groups belong to the existing G01 Native and normal WASM CLI'
        extra = [EMBEDDED_LIBRARY_MODEL, fixture_source, HERE / 'verify_full_geometry.py', HERE / 'verify_lineage.py',
            HERE / 'verify.py', HERE / 'native_tests.py', HERE / 'typecheck.py',
            ROOT / 'Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs',
            ROOT / 'Tests/CADGeometryTests/OriginalNativeRectangleGeometryTests.swift',
            ROOT / 'Tests/CADGeometryTests/CurveTessellationDirectExecutionTests.swift',
            ROOT / 'Tests/CADGeometryTests/OriginalPublicCallerDirectExecutionTests.swift']
        for path in extra:
            relative = str(fixture_relative if path == fixture_source else path.relative_to(ROOT))
            origin = str(path)
            assert relative not in input_origins or input_origins[relative] == origin, 'An input key names different authority origins: ' + relative
            inputs[relative] = digest(path)
            input_origins[relative] = origin
        snapshot = {}
        for relative, expected in inputs.items():
            target = output / 'snapshot' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(input_origins[relative], target)
            assert digest(target) == expected
            snapshot[str(target)] = expected
        receipt = {'status': 'prepared', 'scope': 'Actual full Geometry module and explicitly pinned runtime fixture; no whole-U1 claim.',
            'sourceCount': {'CADCore': len(core), 'CADGeometry': len(geometry)}, 'sourceSHA256': {**core, **geometry},
            'sourceRoot': str(source_root), 'compileCore': args.compile_core,
            'coreProductMode': 'compile authoritative sources' if args.compile_core else 'reuse explicit exact Core prefix' if reused_core else 'reuse exact matching source products',
            'coreReuseReceipt': None if not reused_core else {'path': str(core_receipt), 'sha256': digest(core_receipt),
                'snapshot': str(output / 'CoreReuseReceipt.json'), 'snapshotSHA256': digest(output / 'CoreReuseReceipt.json')},
            'inputOrigins': input_origins,
            'inputSHA256': inputs, 'snapshotSHA256': snapshot, 'coreBuildDefineReferences': [],
            'sourceReceipt': {'path': str(source_receipt), 'sha256': digest(output / 'RootSourceReceipt.json')},
            'sourceReceiptSnapshot': {'path': str(output / 'RootSourceReceipt.json'), 'sha256': digest(output / 'RootSourceReceipt.json')},
            'embeddedLibraryModel': {'url': 'https://docs.swift.org/main/documentation/embeddedswift/libraries/',
                'path': str(EMBEDDED_LIBRARY_MODEL), 'sha256': EMBEDDED_LIBRARY_MODEL_SHA256,
                'swiftLibraryCodeLinkInputs': [], 'libraryEmission': 'module only; client compiles serialized Swift code'},
            'lineageReceipt': {'path': str(LINEAGE), 'sha256': digest(LINEAGE)},
            'asanLineageReceipt': {'path': str(ASAN_LINEAGE), 'sha256': digest(ASAN_LINEAGE)},
            'fixtureRoot': str(fixture_root),
            'fixture': {'path': str(fixture_source), 'sha256': digest(fixture_source), 'expectedOutputLines': expected_output},
            'compilerVersion': lineage['compilerVersion'], 'toolSHA256': lineage['toolSHA256'], 'wasmSDK': lineage['wasmSDK'],
            'nativeSDK': asan_lineage['nativeSDK'], 'nativeLinker': asan_lineage['nativeLinker'],
            'bounds': {'compileLinkSecondsPerLane': COMPILE_SECONDS, 'runtimeSeconds': RUNTIME_SECONDS, 'aggregateRSSBytes': RSS_LIMIT, 'compilerProcessesAtOnce': 1},
            'environment': {'PATHFirst': str(BIN), 'TOOLCHAINS': None, 'ASAN_OPTIONS': environment['ASAN_OPTIONS']},
            'wasmStackBytes': 67108864, 'stackSettingSources': {str(p): digest(p) for p in [ROOT / 'Package.swift', PRODUCT_RECEIPTS / 'wasm/public-compile.json']},
            'phases': [], 'lanes': {}}
        for lane in args.lanes:
            destination = output / lane
            dependencies = destination / 'dependencies'
            dependencies.mkdir(parents=True)
            selected_lineage = asan_lineage if lane == 'asan' else lineage
            retained = selected_lineage['lanes'][lane]
            core_phase = None
            if not args.compile_core and not reused_core:
                core_phase = next(p for p in selected_lineage['phases'] if p['name'] == lane + '-Core-compile')
                assert core_phase['exitCode'] == 0 and core_phase['stopReason'] is None
            if lane == 'asan' and not args.compile_core and not reused_core:
                # This lane passed before an unrelated later WASM output collision.
                for suffix in ['link', 'runtime']:
                    accepted = next(p for p in selected_lineage['phases'] if p['name'] == lane + '-' + suffix)
                    assert accepted['exitCode'] == 0 and accepted['stopReason'] is None
            copied_dependencies = {}
            for source, evidence in retained['dependencies'].items():
                assert digest(source) == evidence['sha256']
                if lane == 'embedded' and not source.endswith('.swiftmodule'):
                    continue
                target = dependencies / Path(source).name
                shutil.copyfile(source, target)
                copied_dependencies[str(target)] = {'source': source, 'sha256': digest(target)}
            for source, expected in ([] if args.compile_core or reused_core else retained['compiledProducts'].items()):
                assert digest(source) == expected
                if lane == 'embedded' and not source.endswith('.swiftmodule'):
                    continue
                target = dependencies / ('CADCore.code.o' if source.endswith('/CADCore.o') else Path(source).name)
                shutil.copyfile(source, target)
                copied_dependencies[str(target)] = {'source': source, 'sha256': digest(target)}
            product_receipt = PRODUCT_RECEIPTS / lane / 'products.json'
            assert digest(product_receipt) == retained['dependencyReceiptSHA256']
            flags = ['-parse-as-library', '-Onone', '-g', '-swift-version', '6', '-package-name', 'swift_cad',
                '-DSWIFT_PACKAGE', '-DDEBUG', '-DNativeExchange', '-whole-module-optimization', '-num-threads', '0', '-j1', '-enable-testing',
                '-I', destination, '-I', dependencies]
            if lane == 'asan':
                flags += ['-sanitize=address', '-sdk', MACSDK, '-target', 'arm64-apple-macos27.0',
                    '-tools-directory', BIN, '-Xclang-linker', '-fuse-ld=' + str(LD)]
            else:
                flags += ['-target', 'wasm32-unknown-wasip1', '-sdk', SDKBASE / 'WASI.sdk',
                '-resource-dir', SDKBASE / ('swift.xctoolchain/usr/lib/swift' if lane == 'embedded' else 'swift.xctoolchain/usr/lib/swift_static'),
                '-static-stdlib', '-tools-directory', BIN, '-Xclang-linker', '-resource-dir', '-Xclang-linker', SDKBASE / 'swift.xctoolchain/usr/lib/swift_static/clang']
            if lane == 'embedded':
                flags += ['-enable-experimental-feature', 'Embedded']
            core_command = None
            if args.compile_core:
                core_response = destination / 'CoreSources.rsp'
                core_response.write_text(''.join('"' + str(output / 'snapshot' / source) + '"\n' for source in sorted(core)))
                core_module = dependencies / 'CADCore.swiftmodule'
                core_object = dependencies / 'CADCore.code.o'
                core_command = [SWIFTC] + flags + ['-module-name', 'CADCore', '-emit-module', '-emit-module-path', core_module]
                if lane != 'embedded':
                    core_command += ['-emit-object', '-o', core_object]
                core_command += ['@' + str(core_response)]
            response = destination / 'GeometrySources.rsp'
            response.write_text(''.join('"' + str(output / 'snapshot' / source) + '"\n' for source in sorted(geometry)))
            module = destination / 'CADGeometry.swiftmodule'
            object_file = destination / 'CADGeometry.code.o'
            compile_command = [SWIFTC] + flags + ['-module-name', 'CADGeometry', '-emit-module', '-emit-module-path', module]
            if lane != 'embedded':
                compile_command += ['-emit-object', '-o', object_file]
            compile_command += ['@' + str(response)]
            executable = destination / ('GeometryPublicFixture' if lane == 'asan' else 'GeometryPublicFixture.wasm')
            fixture = output / 'snapshot' / fixture_relative
            objects = [dependencies / 'CADCore.code.o', dependencies / ('InternalCollectionsUtilities.a' if lane == 'embedded' else 'InternalCollectionsUtilities.o'),
                dependencies / ('HashTreeCollections.a' if lane == 'embedded' else 'HashTreeCollections.o')]
            # Embedded libraries serialize Swift code into modules; only the client emits machine code.
            swift_code_inputs = [] if lane == 'embedded' else [object_file] + objects
            link_command = [SWIFTC] + flags + [fixture] + swift_code_inputs + ['-o', executable]
            if lane != 'asan':
                link_command += ['-Xlinker', '-z', '-Xlinker', 'stack-size=67108864']
            if lane == 'embedded':
                link_command += ['-Xlinker', SDKBASE / 'swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a',
                    '-Xlinker', '-lc++', '-Xlinker', '-lc++abi', '-Xlinker', '-lswift_Concurrency']
            runtime_command = [executable] if lane == 'asan' else ['/usr/local/bin/node', output / 'snapshot/Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs', executable]
            steps = runtime_steps(lane, [str(v) for v in runtime_command], args.runtime_group, expected_output)
            receipt['lanes'][lane] = {'dependencies': copied_dependencies, 'sdkIdentifier': 'macOS27.0' if lane == 'asan' else 'swift-6.4.0-RELEASE_wasm' + ('-embedded' if lane == 'embedded' else ''),
                'retainedCoreCompilePhase': None if args.compile_core else core_phase,
                'platformArchiveSHA256': {str(v): digest(v) for v in link_command if str(v).endswith('.a')},
                'runtimeSteps': steps,
                'dependencyReceiptSHA256': digest(product_receipt), 'responseSHA256': digest(response),
                'commands': {name: [str(v) for v in command] for name, command in [('compile', compile_command), ('link', link_command), ('runtime', runtime_command)]},
                'products': [str(module), str(executable)] if lane == 'embedded' else [str(module), str(object_file), str(executable)]}
            if reused_core:
                previous = reused_core['lanes'][lane]
                phase = next(p for p in reused_core['phases'] if p['name'] == lane + '-core-compile')
                assert phase['exitCode'] == 0 and phase['stopReason'] is None
                assert phase['command'] == previous['commands']['core-compile']
                assert {Path(p).name: item['sha256'] for p, item in previous['dependencies'].items()} == {Path(p).name: item['sha256'] for p, item in copied_dependencies.items()}, 'Core dependency products differ'
                assert phase['rssScope'] in {'sampled PPID-descendant process tree', 'tracked PPID descendants including separate process groups'}
                assert phase['peakRSSBytes'] <= RSS_LIMIT and phase['elapsedSeconds'] <= COMPILE_SECONDS
                assert digest(Path(phase['log'])) == phase['logSHA256']
                command = phase['command']
                expected_flags = [str(v) for v in flags]
                previous_flags = command[1:1 + len(flags)]
                for index, value in enumerate(expected_flags):
                    if index and expected_flags[index - 1] == '-I':
                        assert Path(previous_flags[index]).resolve() == (args.reuse_core_products.resolve() / lane / ('dependencies' if Path(value).name == 'dependencies' else '')).resolve()
                    else:
                        assert previous_flags[index] == value, 'Core compiler flags differ'
                assert command[0] == str(SWIFTC)
                assert command[1 + len(flags):1 + len(flags) + 2] == ['-module-name', 'CADCore']
                response_path = Path(command[-1][1:])
                assert command[-1].startswith('@') and digest(response_path) == previous['coreResponseSHA256']
                assert set(shlex.split(response_path.read_text())) == {str(args.reuse_core_products.resolve() / 'snapshot' / p) for p in core}
                expected_products = {str(Path(v)) for v in previous['coreProducts']}
                assert expected_products == set(previous['compiledCoreProductSHA256'])
                assert {Path(v).name for v in expected_products} == ({'CADCore.swiftmodule'} if lane == 'embedded' else {'CADCore.swiftmodule', 'CADCore.code.o'})
                retained_core = {}
                for source, expected in previous['compiledCoreProductSHA256'].items():
                    assert digest(Path(source)) == expected, 'Retained Core product changed: ' + source
                    target = dependencies / Path(source).name
                    shutil.copyfile(source, target)
                    assert digest(target) == expected
                    retained_core[str(target)] = expected
                    copied_dependencies[str(target)] = {'source': source, 'sha256': expected}
                receipt['lanes'][lane].update(coreProducts=list(retained_core), compiledCoreProductSHA256=retained_core,
                    retainedCoreCompilePhase=phase,
                    reusedCoreProof={'receipt': str(core_receipt), 'receiptSHA256': digest(core_receipt),
                        'compilePhase': phase, 'bounds': reused_core['bounds']})
            if core_command:
                receipt['lanes'][lane]['commands']['core-compile'] = [str(v) for v in core_command]
                receipt['lanes'][lane]['coreResponseSHA256'] = digest(core_response)
                receipt['lanes'][lane]['coreProducts'] = [str(core_module)] if lane == 'embedded' else [str(core_module), str(core_object)]
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    else:
        receipt = json.loads((output / 'receipt.json').read_text())
    def save():
        origins = receipt.get('inputOrigins', {})
        receipt['currentDrift'] = [p for p, h in receipt['inputSHA256'].items() if digest(origins.get(p, ROOT / p)) != h]
        receipt['snapshotDrift'] = [p for p, h in receipt['snapshotSHA256'].items() if digest(p) != h]
        product_hashes = {}
        for selected_lane in receipt['lanes'].values():
            product_hashes.update({p: item['sha256'] for p, item in selected_lane['dependencies'].items()})
            product_hashes.update(selected_lane.get('compiledCoreProductSHA256', {}))
            product_hashes.update(selected_lane.get('compiledProductSHA256', {}))
        receipt['productDrift'] = [p for p, h in product_hashes.items() if digest(p) != h]
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    assert not receipt['currentDrift'] and not receipt['snapshotDrift'] and not receipt['productDrift']
    if args.prepare_only:
        core_mode = 'compile' if receipt.get('compileCore') else 'reuse'
        print(f"PREPARED full Core{receipt['sourceCount']['CADCore']} {core_mode} + Geometry{receipt['sourceCount']['CADGeometry']} fixed inputs; no compiler launched", flush=True)
        return
    def bounded_run(command, log, wall_limit):
        assert RSS_LIMIT == BOUNDED_RSS_BYTES, 'The shared monitor must retain the existing RSS ceiling'
        result = run_bounded_process(command, log, environment,
            deadline=time.monotonic() + wall_limit, stage_limit=wall_limit)
        result['peakRSSBytes'] = result['sampledPeakProcessTreeRSSBytes']
        result['rssScope'] = result['rssAccounting']
        return result
    receipt['status'] = 'running'
    started = time.monotonic()
    for lane in args.lanes:
        lane_started = time.monotonic()
        selected = receipt['lanes'][lane]
        steps = selected.get('runtimeSteps', [{'phase': 'runtime', 'command': selected['commands']['runtime'],
            'requiredOutputLines': receipt['fixture']['expectedOutputLines']}])
        if args.resume_plan and lane in ['asan', 'wasm'] and args.runtime_group:
            assert [step['phase'] for step in steps] == ['runtime-' + group for group in args.runtime_group], 'Resume groups differ from the immutable prepared plan'
        runtime_by_phase = {step['phase']: step for step in steps}
        phases = ['compile'] if args.compile_only else ['compile', 'link'] + list(runtime_by_phase)
        if 'core-compile' in selected['commands']:
            phases.insert(0, 'core-compile')
        if args.reuse_geometry_products:
            old_path = args.reuse_geometry_products.resolve() / 'receipt.json'
            old = json.loads(old_path.read_text())
            if lane in old['lanes'] and 'compiledProductSHA256' in old['lanes'][lane]:
                assert old['sourceSHA256'] == receipt['sourceSHA256']
                assert old['toolSHA256'] == receipt['toolSHA256'] and old['wasmSDK'] == receipt['wasmSDK']
                prior_phase = next(p for p in old['phases'] if p['name'] == lane + '-compile' and p['exitCode'] == 0)
                retained_products = {}
                for source, expected in old['lanes'][lane]['compiledProductSHA256'].items():
                    if lane == 'embedded' and not source.endswith('.swiftmodule'):
                        continue
                    assert digest(source) == expected
                    target = output / lane / Path(source).name
                    shutil.copyfile(source, target)
                    retained_products[str(target)] = expected
                selected['compiledProductSHA256'] = retained_products
                if args.compile_core:
                    core_products = old['lanes'][lane].get('compiledCoreProductSHA256')
                    assert core_products, 'Fresh Core reuse requires its actual compiled product hashes'
                    core_phase = next(p for p in old['phases'] if p['name'] == lane + '-core-compile'
                        and p['exitCode'] == 0 and p.get('stopReason') is None)
                    retained_core = {}
                    for source, expected in core_products.items():
                        if lane == 'embedded' and not source.endswith('.swiftmodule'):
                            continue
                        assert digest(source) == expected
                        target = output / lane / 'dependencies' / Path(source).name
                        shutil.copyfile(source, target)
                        assert digest(target) == expected
                        retained_core[str(target)] = expected
                    assert set(retained_core) == set(selected['coreProducts']), 'Reused Core product set differs'
                    selected['compiledCoreProductSHA256'] = retained_core
                    selected['reusedCoreProof'] = {'receipt': str(old_path), 'receiptSHA256': digest(old_path),
                        'compilePhase': core_phase}
                ppid_accounting = {'sampled PPID-descendant process tree',
                    'tracked PPID descendants including separate process groups'}
                bound_proven = prior_phase.get('rssScope') in ppid_accounting
                selected['reusedGeometryProof'] = {'receipt': str(old_path), 'receiptSHA256': digest(old_path),
                    'compilePhase': prior_phase, 'resourceBoundProven': bound_proven,
                    'resourceLimitation': None if bound_proven else 'The compile receipt does not prove PPID-descendant process-tree RSS accounting.'}
                phases = ['link'] + list(runtime_by_phase)
        for phase in phases:
            log = output / (lane + '-' + phase + '.log')
            is_runtime = phase in runtime_by_phase
            timeout = RUNTIME_SECONDS if is_runtime else max(1, COMPILE_SECONDS - (time.monotonic() - lane_started))
            save()
            command = runtime_by_phase[phase]['command'] if is_runtime else selected['commands'][phase]
            result = bounded_run(command, log, timeout)
            result.update({'name': lane + '-' + phase, 'log': str(log), 'wallLimitSeconds': timeout})
            receipt['phases'].append(result)
            save()
            print(json.dumps({k: result[k] for k in ['name', 'exitCode', 'elapsedSeconds', 'peakRSSBytes', 'stopReason']}), flush=True)
            if result['exitCode'] or result['stopReason'] or receipt['currentDrift'] or receipt['snapshotDrift'] or receipt['productDrift']:
                receipt['status'] = 'failed'
                save()
                raise SystemExit(1)
            if phase == 'compile':
                selected['compiledProductSHA256'] = {p: digest(p) for p in selected['products'][:-1]}
            if phase == 'core-compile':
                selected['compiledCoreProductSHA256'] = {p: digest(p) for p in selected['coreProducts']}
            if is_runtime:
                required = runtime_by_phase[phase]['requiredOutputLines']
                if not all(line in log.read_text().splitlines() for line in required):
                    receipt['status'] = 'failed'
                    receipt['failure'] = 'Missing exact runtime oracle lines for ' + lane + '-' + phase
                    save()
                    raise SystemExit(1)
                selected['executableSHA256'] = digest(selected['products'][-1])
                matched = selected.setdefault('matchedOracleLines', [])
                matched.extend(line for line in required if line not in matched)
            save()
        if not args.compile_only:
            required = {line for step in steps for line in step['requiredOutputLines']}
            if set(selected['matchedOracleLines']) != required:
                receipt['status'] = 'failed'
                receipt['failure'] = 'Cumulative runtime oracle lines differ from the prepared plan'
                save()
                raise SystemExit(1)
        selected['elapsedSeconds'] = time.monotonic() - lane_started
    receipt['status'] = 'compiled-only' if args.compile_only else 'passed'
    receipt['elapsedSeconds'] = time.monotonic() - started
    save()
    print('PASS full Geometry module compilation only; no client/runtime; drift=0' if args.compile_only else 'PASS selected full Geometry portable lanes; drift=0', flush=True)


if __name__ == '__main__':
    main()
