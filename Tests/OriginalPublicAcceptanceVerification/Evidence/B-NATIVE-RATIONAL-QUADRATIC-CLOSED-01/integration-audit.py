#!/usr/bin/env python3
"""Audit this finite cell without rebuilding; delivery requires explicit --deliver.

The frozen summary supplies cell, groups, freshProduction {absolute: {sha256,
bytes}}, accepted [{lane, receipt, receiptSHA256, groups, modules}], observations,
manifest {path, sha256}, diagnostics, and issued {summary, sha256, manifest,
manifestSHA256}. Each module supplies receipt, sha256, moduleName,
command (the saved compiler command JSON). Optional historicalComparators maps
an original absolute path to {path, sha256}; only an exact path/hash pair applies.
Optional logPaths maps run labels to saved logs; otherwise use <label>.log next
to the receipt. All metadata paths are evidence-relative unless absolute.
Accepted parts may select successRunLabels from a rejected receipt, preserving
its raw state. scope is current-boundary or source-authority-only, and
productionScope names exactly the current sources used by that accepted scope.
The latter supplies assembly (the actual link receipt) and sourceFunction
{oldFixture, sha256, first: sourceCurve, after: denominatorControls}.
"""

import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path


ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
INDEPENDENT = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
MAIN = Path('/Users/1amageek/Desktop/3D/swift-CAD')
BASE = '0422fa0c6151467da32b5fdf7e00bccbc4f5d64f'
CELL = 'B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01'
RELATIVE = Path('Tests/OriginalPublicAcceptanceVerification/Evidence') / CELL
EVIDENCE = ROOT / RELATIVE
PRIOR = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/CS-REVOLUTION-AXIS-FIBER-01/integration.json')
LANES = {'native', 'asan', 'wasm', 'embedded'}
MODULE_COUNTS = {'NativeDomainAdapters': 32, 'QuadraticBoundarySources': 5}
SOURCE_NAMES = {'OriginalRationalQuadraticBoundaryReceipt.swift',
                'OriginalRationalQuadraticBoundaryIssuing.swift',
                'DefaultOriginalRationalQuadraticBoundaryIssuer.swift',
                'BSplineCurve2D+OriginalSourceReading.swift',
                'OriginalBSplinePcurveSnapshotProvider.swift'}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def git(directory, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=directory, timeout=30)


def read(path):
    return json.loads(Path(path).read_text())


def audit():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('implementation', help='full committed implementation SHA')
    parser.add_argument('--summary', type=Path, default=EVIDENCE / 'summary.json')
    parser.add_argument('--deliver', action='store_true', help='fast-forward main only after all comparisons pass')
    arguments = parser.parse_args()
    started = time.monotonic()
    cache = {}
    references = 0

    def sha(path):
        path = Path(path)
        before = path.stat()
        key = (str(path), before.st_size, before.st_mtime_ns, before.st_ino)
        if key not in cache:
            require(time.monotonic() - started < 180, 'audit wall bound exceeded')
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
            after = path.stat()
            require((before.st_size, before.st_mtime_ns, before.st_ino) ==
                    (after.st_size, after.st_mtime_ns, after.st_ino), f'changed while hashing: {path}')
            cache[key] = digest.hexdigest()
        return cache[key]

    def check(path, expected):
        nonlocal references
        require(sha(path) == expected, f'SHA mismatch: {path}')
        references += 1

    def locate(name):
        path = Path(name)
        return path if path.is_absolute() else EVIDENCE / path

    def exact_head(directory, head):
        require(git(directory, 'rev-parse', 'HEAD').decode().strip() == head, f'HEAD: {directory}')
        require(not git(directory, 'status', '--porcelain=v1', '-z'), f'dirty checkout: {directory}')

    implementation = arguments.implementation
    require(git(ROOT, 'rev-parse', implementation).decode().strip() == implementation, 'full implementation SHA required')
    exact_head(ROOT, implementation)
    exact_head(MAIN, BASE)
    require(git(MAIN, 'branch', '--show-current').decode().strip() == 'main', 'main branch required')
    independent_head = git(INDEPENDENT, 'rev-parse', 'HEAD').decode().strip()
    require(independent_head in {BASE, implementation}, 'independent checkout must be baseline or implementation')
    exact_head(INDEPENDENT, independent_head)
    subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, implementation], cwd=ROOT, check=True, timeout=30)
    if independent_head == BASE:
        subprocess.run(['git', 'merge', '--ff-only', '--quiet', implementation], cwd=INDEPENDENT, check=True, timeout=30)
    exact_head(INDEPENDENT, implementation)

    prior = read(ROOT / PRIOR)
    require(hashlib.sha256(git(ROOT, 'show', f'{BASE}:{PRIOR}')).hexdigest() == sha(ROOT / PRIOR),
            'inherited integration differs from baseline')
    summary_path = arguments.summary.resolve()
    summary_path.relative_to(EVIDENCE)
    summary = read(summary_path)
    require(summary['cell'] == CELL, 'cell mismatch')
    groups = set(summary['groups'])
    require(groups and len(groups) == len(summary['groups']), 'nonempty unique group list required')
    fresh = {name: item['sha256'] for name, item in summary['freshProduction'].items()}
    require(len(fresh) == sum(MODULE_COUNTS.values()), 'expected 32 domain bodies and 5 source bodies')
    for name, item in summary['freshProduction'].items():
        Path(name).relative_to(ROOT)
        check(name, item['sha256'])
        check(locate(item['bytes']), item['sha256'])

    manifest_path = locate(summary['manifest']['path'])
    manifest_path.relative_to(EVIDENCE)
    check(manifest_path, summary['manifest']['sha256'])
    durable = {}
    for name, value in read(manifest_path)['files'].items():
        path = EVIDENCE / name
        path.resolve().relative_to(EVIDENCE)
        expected = value['sha256'] if isinstance(value, dict) else value
        check(path, expected)
        durable[str(path.relative_to(ROOT))] = expected
    for path in [summary_path, manifest_path, EVIDENCE / 'REVIEW.md', EVIDENCE / 'VERIFICATION.md']:
        durable[str(path.relative_to(ROOT))] = sha(path)
    issued_metadata = summary['issued']
    issued_path = locate(issued_metadata['summary'])
    check(issued_path, issued_metadata['sha256'])
    issued_summary = read(issued_path)
    immutable_inputs = {}
    for item in issued_summary.get('compilerInputs', {}).values():
        path = locate(item['path'])
        check(path, item['sha256'])
        immutable_inputs[item['sha256']] = path
    for lane in issued_summary['lanes'].values():
        for binding in lane.get('compiledBindings17', []):
            for kind in ['original', 'generated']:
                snapshot = binding[kind + 'Snapshot']
                path = locate(snapshot['path'])
                digest = binding[kind + 'SHA256']
                require(snapshot['sha256'] == digest, 'issued immutable snapshot hash binding')
                check(path, digest)
                immutable_inputs[digest] = path

    def inspect(metadata, receipt_key='receiptSHA256', successful_runs=True, historical_observation=False):
        path = locate(metadata['receipt'])
        check(path, metadata[receipt_key])
        record = read(path)
        comparator_sets = [metadata.get('historicalComparators', {}), record.get('historicalComparators', {})]
        for field in ['checks', 'products', 'freshProduction']:
            for name, expected in record.get(field, {}).items():
                comparator = next((mapping[name] for mapping in comparator_sets
                                   if name in mapping and mapping[name]['sha256'] == expected), None)
                if comparator is not None:
                    check(locate(comparator['path']), expected)
                elif expected in immutable_inputs:
                    # Exact retained bytes compare an old input; they do not assert current-source equality.
                    check(immutable_inputs[expected], expected)
                else:
                    check(name, expected)
        labels = {}
        for run in record['runs']:
            label = run['label']
            require(label not in labels, f'duplicate run: {path}: {label}')
            labels[label] = run
            saved_log = metadata.get('logPaths', {}).get(label)
            check(locate(saved_log) if saved_log else path.parent / f'{label}.log', run['logSHA256'])
            if 'ownedDescendantsRemaining' in run:
                require(not run['ownedDescendantsRemaining'], f'owned process remains: {path}: {label}')
            else:
                require(historical_observation and
                        metadata[receipt_key] == '434c08d8240e60d2971fa0e053d94833206644d0ba2290dcea87acf46efe7446' and
                        path == EVIDENCE / 'native-observation-v1/receipt.json' and
                        record.get('state') == 'observed-public-unsupportedCoverage',
                        f'owned process observation missing: {path}: {label}')
            if successful_runs:
                require(run['exitCode'] == 0 and not run['timedOut'], f'run failed: {path}: {label}')
        return record, labels

    covered = {lane: set() for lane in LANES}
    accepted = []
    for metadata in summary['accepted']:
        lane = metadata['lane']
        require(lane in LANES and not covered[lane].intersection(metadata['groups']), 'duplicate or unknown lane groups')
        record, labels = inspect(metadata, successful_runs=False)
        require(record['cell'] == CELL and record['lane'] == lane and
                record['state'] in {'compiled', 'accepted-selected-current-snapshot'} and record['preAndPostAdmission'] is True,
                'accepted receipt status')
        require(record['success'] is (record['state'] == 'accepted-selected-current-snapshot'), 'raw receipt status binding')
        require(set(metadata['groups']) <= set(record['groups']), 'selected groups must belong to the raw receipt')
        scope = metadata.get('scope', 'current-boundary')
        require(scope in {'source-authority-only', 'current-boundary'}, 'unknown accepted causal scope')
        source_only = scope == 'source-authority-only'
        expected_scope = {name: digest for name, digest in fresh.items() if Path(name).name in SOURCE_NAMES} if source_only else fresh
        require(len(expected_scope) == (5 if source_only else 37) and
                metadata.get('productionScope', fresh) == expected_scope and
                all(record['freshProduction'].get(name) == digest for name, digest in expected_scope.items()),
                'accepted causal production scope differs')
        if source_only:
            require(lane == 'native' and metadata['groups'] == ['source'], 'source-only reuse cannot include boundary groups')
            function = metadata['sourceFunction']
            require(function['first'] == 'sourceCurve' and function['after'] == 'denominatorControls', 'source function scope')
            markers = [b'    static func sourceCurve()', b'    static func denominatorControls()']
            for fixture in [locate(function['oldFixture']), ROOT / 'Tests/OriginalPublicAcceptanceVerification/RationalQuadraticBoundaryAcceptance.swift']:
                body = fixture.read_bytes()
                first = body.index(markers[0])
                block = body[first:body.index(markers[1], first)]
                require(hashlib.sha256(block).hexdigest() == function['sha256'], 'source function/helper bytes differ')
        else:
            require(record['freshProduction'] == fresh, 'current boundary source snapshot differs')
        expected_runs = {f'runtime-{group}' for group in metadata['groups']}
        require(set(metadata.get('successRunLabels', expected_runs)) == expected_runs and expected_runs <= labels.keys(),
                'runtime group binding')
        require(all(labels[label]['exitCode'] == 0 and not labels[label]['timedOut'] for label in expected_runs),
                'selected runtime group did not succeed')
        assembly = metadata.get('assembly', metadata)
        assembly_record, assembly_labels = (inspect(assembly, successful_runs=False) if 'assembly' in metadata else (record, labels))
        require('compile-link-cell' in assembly_labels and assembly_labels['compile-link-cell']['exitCode'] == 0 and
                not assembly_labels['compile-link-cell']['timedOut'], 'actual successful compiler/link run required')
        if source_only:
            products = [name for name in record['products'] if not name.endswith(('.a', '.swiftmodule'))]
            require(len(products) == 1 and assembly_record['products'].get(products[0]) == record['products'][products[0]] and
                    products[0] in labels['runtime-source']['command'], 'source runtime must consume its actual compiled product')
        receipt_path = locate(assembly['receipt'])
        require(read(locate(assembly.get('command', str(receipt_path.parent / 'compile-command.json')))) ==
                assembly_labels['compile-link-cell']['command'], 'compiler/link command mismatch')
        modules = set()
        module_sources = set()
        for module in metadata['modules']:
            name = module['moduleName']
            require(name in MODULE_COUNTS and name not in modules, 'module scope mismatch')
            modules.add(name)
            module_record, module_labels = inspect(module, 'sha256')
            require(module_record['lane'] == lane and len(module_record['freshProduction']) == MODULE_COUNTS[name] and
                    all(record['freshProduction'].get(path) == digest for path, digest in module_record['freshProduction'].items()),
                    f'module selected source mismatch: {lane}: {name}')
            require(not module_sources.intersection(module_record['freshProduction']), 'module source responsibilities overlap')
            module_sources.update(module_record['freshProduction'])
            label = 'compile-' + name
            require(set(module_labels) == {label}, f'exact module run required: {lane}: {name}')
            command = read(locate(module['command']))
            require(command == module_labels[label]['command'], f'module compiler command mismatch: {lane}: {name}')
            selected = [token for token in command if token.endswith('.swift')]
            generated_sources = module.get('generatedSources', {})
            require(not generated_sources or (name == 'QuadraticBoundarySources' and len(generated_sources) == 2 and
                    {Path(item['original']).name for item in generated_sources.values()} ==
                    {'BSplineCurve2D+OriginalSourceReading.swift', 'OriginalBSplinePcurveSnapshotProvider.swift'}),
                    'generated source adapter scope')
            for compiled_argument, binding in generated_sources.items():
                require(binding['prefix'] == 'import L0\nimport L1\n@testable import SourceIssuer\n@testable import struct CADGeometry.BSplineCurve2D\n',
                        'generated source prefix is limited to the admitted nominal imports')
                require(compiled_argument in selected and
                        module_record['freshProduction'].get(binding['original']) == binding['originalSHA256'] and
                        module_record['checks'].get(compiled_argument) == binding['sha256'], 'generated source receipt binding')
                check(locate(binding['originalSnapshot']), binding['originalSHA256'])
                check(locate(binding['path']), binding['sha256'])
                expected_bytes = binding['prefix'].encode() + locate(binding['originalSnapshot']).read_bytes()
                require(hashlib.sha256(expected_bytes).hexdigest() == binding['sha256'], 'generated import prefix must preserve exact source body')
            selected_originals = [generated_sources[token]['original'] if token in generated_sources else token for token in selected]
            require(len(selected) == MODULE_COUNTS[name] and set(selected_originals) == set(module_record['freshProduction']),
                    f'compiler selected bodies mismatch: {lane}: {name}')
            archives = [path for path in module_record['products'] if path.endswith('.a')]
            require(len(archives) == 1 and archives[0] in assembly_labels['compile-link-cell']['command'],
                    f'actual link must consume the admitted module archive: {lane}: {name}')
        require(modules == MODULE_COUNTS.keys(), 'both actual module receipts required')
        require(module_sources == record['freshProduction'].keys(), 'module receipts must cover all 37 recorded bodies')
        covered[lane].update(metadata['groups'])
        accepted.append({**metadata, 'rawReceiptSuccess': record['success'], 'rawReceiptState': record['state']})
    require(all(value == groups for value in covered.values()), 'four-lane group coverage incomplete')

    retained_products = {}
    for observation in summary['observations']:
        record, labels = inspect(observation, historical_observation=True)
        require(record['state'] == 'observed-public-unsupportedCoverage' and
                record['typedStop'] == 'NativeExactRelationFailure.unsupportedCoverage' and
                record['noClippedSuccess'] is True, 'historical public stop was relabeled')
        require('compile-link-observation' in labels and 'runtime-observation' in labels, 'historical observation runs')
        legacy_product = EVIDENCE / 'native-observation-v1/RationalQuadraticBoundaryProof'
        legacy_relative = str(legacy_product.relative_to(ROOT))
        if legacy_relative in durable:
            expected = 'd16f5cba22dde1a0608902bf750fda1ba25a5d732ae730ee6bbc87099263419a'
            require(observation['receiptSHA256'] == '434c08d8240e60d2971fa0e053d94833206644d0ba2290dcea87acf46efe7446' and
                    locate(observation['receipt']) == EVIDENCE / 'native-observation-v1/receipt.json' and
                    durable[legacy_relative] == expected and record['products'].get(str(legacy_product)) == expected,
                    'legacy retained product must bind the exact original receipt and manifest')
            command = labels['compile-link-observation']['command']
            require(command[command.index('-o') + 1] == str(legacy_product) and
                    labels['runtime-observation']['command'][0] == str(legacy_product),
                    'legacy retained product must be the actual compile output and runtime input')
            require(not git(ROOT, 'ls-files', '--', legacy_relative), 'legacy product reference must be untracked')
            retained_products[legacy_relative] = dict(originalPath=str(legacy_product), sha256=expected,
                                                     receiptSHA256=observation['receiptSHA256'])
            del durable[legacy_relative]

    diagnostics = summary['diagnostics']
    for metadata in diagnostics:
        require(bool(metadata['scope']), 'historical diagnostic scope required')
        record, _ = inspect(metadata, successful_runs=False)
        require(record.get('success') is not True, 'rejected historical diagnostic cannot count as accepted')

    require(issued_summary['cell'] == CELL and set(issued_summary['lanes']) == LANES, 'issued four-lane scope')
    issued_manifest_path = locate(issued_metadata['manifest'])
    check(issued_manifest_path, issued_metadata['manifestSHA256'])
    issued_files = read(issued_manifest_path)['files']
    for name, digest in issued_files.items():
        check(EVIDENCE / name, digest)
        relative = str(RELATIVE / name)
        require(relative not in durable or durable[relative] == digest, 'issued manifest conflicts with main manifest')
        durable[relative] = digest
    issued_fresh = None
    for lane, metadata in issued_summary['lanes'].items():
        combined = {**metadata, 'historicalComparators': issued_metadata.get('historicalComparators', {})}
        record, labels = inspect(combined)
        require(record['success'] is True and record['state'] == 'accepted-issued-changed-path' and
                record['preAndPostAdmission'] is True and record['lane'] == lane and
                len(record['freshProduction']) == 17, f'issued accepted scope: {lane}')
        if issued_fresh is None:
            issued_fresh = record['freshProduction']
        require(record['freshProduction'] == issued_fresh, 'issued selected source snapshot differs across lanes')
        require('compile-proof' in labels and 'runtime-issued' in labels, 'issued actual compiler/runtime required')
        receipt_path = locate(metadata['receipt'])
        require(read(receipt_path.parent / 'compile-proof.json') == labels['compile-proof']['command'],
                'issued proof compiler command mismatch')
        compiler_metadata = metadata.get('compilerReceipt')
        module_path = locate(compiler_metadata['path']) if compiler_metadata else receipt_path.parent / 'module-receipt.json'
        module_digest = compiler_metadata['sha256'] if compiler_metadata else issued_files[str(module_path.relative_to(EVIDENCE))]
        module_record, module_labels = inspect(dict(receipt=str(module_path), receiptSHA256=module_digest,
            historicalComparators=issued_metadata.get('historicalComparators', {})))
        require(module_record['freshProduction'] == issued_fresh and module_record['lane'] == lane,
                'issued module source snapshot mismatch')
        if lane == 'native' and not module_labels:
            compiler_metadata = issued_summary['nativeCompilerReceipt']
            compiler_record, module_labels = inspect(dict(receipt=compiler_metadata['path'],
                receiptSHA256=compiler_metadata['sha256'],
                historicalComparators=issued_metadata.get('historicalComparators', {})))
            require(compiler_record['freshProduction'] == issued_fresh and
                    compiler_record['products'] == module_record['products'], 'Native reused issued module binding')
        require(set(module_labels) == {'compile-module'}, 'issued actual module compiler run required')
        command = module_labels['compile-module']['command']
        selected = [name for name in command if name.endswith('.swift')]
        require(len(selected) == 17 and {Path(name).name for name in selected} ==
                {Path(name).name for name in issued_fresh}, 'issued compiler selected body scope')
        bindings = metadata.get('compiledBindings17')
        if bindings is not None:
            require(len(bindings) == 17 and {item['generatedPath'] for item in bindings} == set(selected),
                    'issued compiled binding coverage')
            for binding in bindings:
                require(issued_fresh.get(binding['originalPath']) == binding['originalSHA256'] and
                        module_record['checks'].get(binding['generatedPath']) == binding['generatedSHA256'],
                        'issued original/generated receipt binding')
                original = locate(binding['originalSnapshot']['path']).read_bytes()
                generated = locate(binding['generatedSnapshot']['path']).read_bytes()
                require(original and generated.endswith(original) and binding['exactSuffix'] is True and
                        hashlib.sha256(generated[:-len(original)]).hexdigest() == binding['prefixSHA256'],
                        'issued exact original suffix/prefix binding')
        assembly_prefix = None
        for generated in selected:
            check(generated, module_record['checks'][generated])
            original = next(Path(name) for name in issued_fresh if Path(name).name == Path(generated).name)
            original_bytes = original.read_bytes()
            generated_bytes = Path(generated).read_bytes()
            require(original_bytes and generated_bytes.endswith(original_bytes), 'issued compiler must retain exact original body')
            prefix = generated_bytes[:-len(original_bytes)]
            if assembly_prefix is None:
                assembly_prefix = prefix
            require(prefix == assembly_prefix, 'issued generated bodies must share the admitted assembly prefix')
        archives = [name for name in module_record['products'] if name.endswith('.a')]
        require(len(archives) == 1 and archives[0] in labels['compile-proof']['command'],
                'issued proof must link its actual admitted module archive')
    for item in issued_summary.get('compilerInputs', {}).values():
        check(locate(item['path']), item['sha256'])
    current = dict(fresh)
    for name, digest in issued_fresh.items():
        require(name not in current or current[name] == digest, 'Native and issued source snapshots disagree')
        check(name, digest)
        current[name] = digest

    sources = dict(prior['sourcePremises'])
    updates = {}
    for name, digest in current.items():
        relative = str(Path(name).relative_to(ROOT))
        if sources.get(relative) != digest:
            updates[relative] = {'before': sources.get(relative), 'after': digest}
        sources[relative] = digest
    changed, deleted = {}, []
    for value in git(ROOT, 'diff', '--name-only', '-z', BASE, implementation).split(b'\0'):
        if value:
            relative = value.decode()
            if (ROOT / relative).is_file():
                changed[relative] = sha(ROOT / relative)
            else:
                deleted.append(relative)
    files = dict(sources)
    for mapping in [changed, durable]:
        for relative, digest in mapping.items():
            require(relative not in files or files[relative] == digest, f'immutable premise changed: {relative}')
            files[relative] = digest
    for relative, digest in files.items():
        check(ROOT / relative, digest)
        check(INDEPENDENT / relative, digest)
    for relative in deleted:
        require(not (ROOT / relative).exists() and not (INDEPENDENT / relative).exists(), f'deletion mismatch: {relative}')
    tracked = {value.decode() for value in git(ROOT, 'ls-files', '-z', '--', *durable).split(b'\0') if value}
    require(tracked == durable.keys(), 'all remaining durable manifest entries must be tracked')

    protected = prior['protectedDrafts']

    def protected_check():
        for name, directory in [('source', '/private/tmp/cad-di-m4-source-support-20261009'),
                                ('consumer', '/private/tmp/cad-di-m6-consumers-20261009')]:
            directory = Path(directory)
            record = protected[name]
            require(len(record['files']) == (18 if name == 'source' else 264), 'protected snapshot count')
            require(git(directory, 'rev-parse', 'HEAD').decode().strip() == record['head'], 'protected HEAD')
            index = Path(git(directory, 'rev-parse', '--git-path', 'index').decode().strip())
            check(index if index.is_absolute() else directory / index, record['indexSHA256'])
            require(hashlib.sha256(git(directory, 'status', '--porcelain=v1', '-z')).hexdigest() ==
                    record['statusSHA256'], 'protected status')
            for relative, digest in record['files'].items():
                check(directory / relative, digest)
        check('/Users/1amageek/.codex/worktrees/source-consumer-handoff-recovery/pending-public-publisher.patch',
              protected['patchSHA256'])

    protected_check()
    exact_head(ROOT, implementation)
    exact_head(INDEPENDENT, implementation)
    exact_head(MAIN, BASE)
    independent_seconds = time.monotonic() - started
    if arguments.deliver:
        subprocess.run(['git', 'merge', '--ff-only', '--quiet', implementation], cwd=MAIN, check=True, timeout=30)
        exact_head(MAIN, implementation)
        for relative, digest in files.items():
            check(MAIN / relative, digest)
        for relative in deleted:
            require(not (MAIN / relative).exists(), f'main deletion mismatch: {relative}')
        protected_check()
    result = dict(cell=CELL, implementationCommit=implementation, mainBefore=BASE,
                  mainHead=implementation if arguments.deliver else BASE, delivered=arguments.deliver,
                  independentCheckout=str(INDEPENDENT), inheritedIntegration=str(PRIOR),
                  inheritedIntegrationSHA256=sha(ROOT / PRIOR), sourcePremises=sources, premiseUpdates=updates,
                  changedInputs=changed, deletedInputs=deleted, acceptedScopedReceipts=accepted,
                  observations=summary['observations'], diagnostics=diagnostics, issued=issued_metadata,
                  historicalObservationLimits='Original unsupported observation records timeout/CPU/exit/log/RSS, not owned-descendant cleanup; it supplies no accepted owner-lifetime evidence.',
                  nativeSelectedBodies=37, issuedSelectedBodies=17, uniqueCurrentSourceBodies=len(current),
                  durableEvidence=durable, protectedDrafts=protected,
                  retainedProductReferences=retained_products,
                  auditReferences=references, uniqueArtifacts=len(cache), independentSeconds=independent_seconds,
                  elapsedSeconds=time.monotonic() - started, auditScriptSHA256=sha(__file__), buildOrRuntimeRepeated=False)
    output = ROOT / '.build/rational-quadratic-boundary-integration.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['cell', 'implementationCommit', 'mainHead', 'delivered',
                                                  'auditReferences', 'uniqueArtifacts', 'elapsedSeconds']}))


if __name__ == '__main__':
    audit()
