#!/usr/bin/env python3
"""Check the finite Native identity-composition packet without rebuilding.

The independent checkout may fast-forward to the committed implementation.
Only explicit --deliver may fast-forward the user's clean main checkout.
All accepted groups must bind actual successful compiler/runtime receipts;
diagnostics retain their original status and never count as acceptance.
"""

import argparse
import difflib
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path


ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
INDEPENDENT = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
MAIN = Path('/Users/1amageek/Desktop/3D/swift-CAD')
BASE = '7cdadc501f948f8f7ec0b8321e2e9a7ff1d2da7b'
CELL = 'S-NATIVE-IDENTITY-COMPOSITION-01'
RELATIVE = Path('Tests/OriginalPublicAcceptanceVerification/Evidence') / CELL
EVIDENCE = ROOT / RELATIVE
PRIOR = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-DECLARED-WHOLE-EDGE-01/integration.json')
LANES = {'native', 'asan', 'wasm', 'embedded'}
GROUPS = {'complete', 'controls', 'exact', 'work', 'storage', 'cancel'}
CURVE = ROOT / 'Sources/CADGeometry/CertifiedSphereConeIntersectionCurve.swift'
CURRENT_CURVE = '585f163d5424e7a7ce978469067dcd8c7f24596800d7e1beec62466dafdc8351'
CACHED_CURVE = 'df15cecad78b967d08a07862cc57459d581c5cbe142f1c5915fed8582faca967'
SUMMARY_SHA256 = 'c5a7ec090e8ab92dce965418b6998d1bc2412195cb2c99da2e48ebcc7102627e'
MANIFEST_SHA256 = '8771ca0838f56aea0ba37f966ea0c6ac3accaa4515ac6f295bee14fcccb79224'
AUTHORITIES = {
    'fixture': ROOT / 'Tests/OriginalPublicAcceptanceVerification/NativeIdentityCompositionAcceptance.swift',
    'runner': ROOT / 'Tests/OriginalPublicAcceptanceVerification/NativeIdentityCompositionAcceptance.py',
}


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
    parser.add_argument('--deliver', action='store_true')
    arguments = parser.parse_args()
    require(not (EVIDENCE / 'F1/summary.json').exists(),
            'F1 current-source binding remains open; acceptance delivery is disabled')
    require(SUMMARY_SHA256 is not None and MANIFEST_SHA256 is not None, 'final packet hashes are not frozen')
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
        return path if path.is_absolute() else ROOT / path

    def entry(item):
        path = locate(item['path'])
        check(path, item['sha256'])
        if 'bytes' in item:
            require(path.stat().st_size == item['bytes'], f'byte count: {path}')
        return path

    def exact_head(directory, head):
        require(git(directory, 'rev-parse', 'HEAD').decode().strip() == head, f'HEAD: {directory}')
        require(not git(directory, 'status', '--porcelain=v1', '-z'), f'dirty checkout: {directory}')

    implementation = arguments.implementation
    require(git(ROOT, 'rev-parse', implementation).decode().strip() == implementation,
            'full implementation SHA required')
    exact_head(ROOT, implementation)
    exact_head(MAIN, BASE)
    require(git(MAIN, 'branch', '--show-current').decode().strip() == 'main', 'main branch required')
    independent_head = git(INDEPENDENT, 'rev-parse', 'HEAD').decode().strip()
    exact_head(INDEPENDENT, independent_head)
    for ancestor, descendant in [(BASE, independent_head), (independent_head, implementation)]:
        subprocess.run(['git', 'merge-base', '--is-ancestor', ancestor, descendant], cwd=ROOT, check=True, timeout=30)
    if independent_head != implementation:
        subprocess.run(['git', 'merge', '--ff-only', '--quiet', implementation], cwd=INDEPENDENT, check=True, timeout=30)
    exact_head(INDEPENDENT, implementation)

    prior = read(ROOT / PRIOR)
    require(hashlib.sha256(git(ROOT, 'show', f'{BASE}:{PRIOR}')).hexdigest() == sha(ROOT / PRIOR),
            'inherited whole-edge integration differs from baseline')
    sources = dict(prior['sourcePremises'])
    updates = {}
    require(len(sources) == 2170, 'expected unchanged 2170 source premises')
    summary_path = arguments.summary.resolve()
    summary_path.relative_to(EVIDENCE)
    check(summary_path, SUMMARY_SHA256)
    summary = read(summary_path)
    require(summary['cell'] == CELL and summary['cellComplete'] is False, 'finite composition cell scope')
    require(summary['sourceBodies'] == 0 and summary['freshUpperBodies'] == 0 and
            summary['reusedSelf4Bodies'] == 4 and summary['rebuiltLowerBodies'] == 0,
            'no new production or module compilation')
    selected = summary['selectedProduction4']
    require(len(selected) == 4, 'four selected reused self bodies')
    for name, digest in selected.items():
        relative = str(Path(name).relative_to(ROOT))
        require(sources.get(relative) == digest, 'selected body differs from inherited source premise')
        check(name, digest)
    for key in ['fixture', 'runner']:
        entry(summary[key])
        check(AUTHORITIES[key], summary[key]['sha256'])
    manifest_path = entry(summary['manifest'])
    require(summary['manifest']['sha256'] == MANIFEST_SHA256, 'frozen manifest binding')
    manifest = read(manifest_path)
    archived, durable = {}, {}

    def inherited_text(path, digest):
        relative = str(path.relative_to(ROOT))
        if prior['durableEvidence'].get(relative) == digest:
            return True
        require(relative.startswith('Tests/OriginalPublicAcceptanceVerification/Evidence/'),
                'historical text must belong to committed acceptance evidence')
        return hashlib.sha256(git(ROOT, 'show', f'{BASE}:{relative}')).hexdigest() == digest

    for original in manifest['originTuples']:
        path = entry(original['retained'])
        require(original['sha256'] == original['retained']['sha256'], 'exact original/hash tuple')
        key = (original['originalPath'], original['sha256'])
        require(key not in archived or archived[key] == path, 'unambiguous exact original/hash binding')
        archived[key] = path
    for name, metadata in manifest['files'].items():
        path = locate(name)
        digest = metadata if isinstance(metadata, str) else metadata['sha256']
        check(path, digest)
        if isinstance(metadata, dict) and 'bytes' in metadata:
            require(path.stat().st_size == metadata['bytes'], 'manifest bytes')
        if not path.resolve().is_relative_to(EVIDENCE):
            require(inherited_text(path, digest), 'external manifest input must match exact inherited evidence')
        durable[str(path.relative_to(ROOT))] = digest
    own_paths = [locate(name) for name in manifest['files'] if locate(name).resolve().is_relative_to(EVIDENCE)]
    require(len(own_paths) == manifest['ownCASFiles'] and
            sum(path.stat().st_size for path in own_paths) == manifest['ownCASBytes'], 'own CAS count/bytes')
    for path in [summary_path, manifest_path, EVIDENCE / 'REVIEW.md', EVIDENCE / 'VERIFICATION.md']:
        durable[str(path.relative_to(ROOT))] = sha(path)
    whole_summary_path = ROOT / PRIOR.parent / 'summary.json'
    check(whole_summary_path, prior['durableEvidence'][str(whole_summary_path.relative_to(ROOT))])
    whole_summary = read(whole_summary_path)
    whole_manifest = read(entry(whole_summary['manifest']))
    for name, item in whole_manifest['files'].items():
        archived[(name, item['sha256'])] = entry(item)
    cert_summary_path = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/acceptance/summary.json'
    require(inherited_text(cert_summary_path, sha(cert_summary_path)), 'inherited CERT summary')
    cert_summary = read(cert_summary_path)
    for name, item in read(entry(cert_summary['manifest']))['files'].items():
        archived[(name, item['sha256'])] = entry(item)
    nominal = prior['cachedCertifiedNominal']
    require(nominal == whole_summary['cachedCertifiedNominal'] == cert_summary['cachedCertifiedNominal'] and
            nominal['currentSHA256'] == CURRENT_CURVE and nominal['originalPath'] == str(CURVE),
            'inherited cached/current Certified nominal distinction')
    original = CURVE.read_text()
    check(CURVE, CURRENT_CURVE)
    port_wrapper = original.rindex('\nextension CertifiedSphereConeIntersectionCurve {')
    cached_bytes = (original[:port_wrapper].rstrip('\n') + '\n').encode()
    cached_path = entry(nominal['cachedBase'])
    require(nominal['cachedBase']['sha256'] == CACHED_CURVE and cached_path.read_bytes() == cached_bytes and
            len(original[port_wrapper:].splitlines()) == 40, 'only exact additive port differs from cached nominal')
    archived[(str(CURVE), CACHED_CURVE)] = cached_path

    def saved_input(name, expected, comparators=None):
        comparator = (comparators or {}).get(name)
        if comparator is not None:
            old_hash = comparator['sha256']
            path = archived.get((comparator['path'], old_hash))
            path = path if path is not None else entry(comparator)
            check(path, old_hash)
            require(path in archived.values() or inherited_text(path, old_hash), 'exact durable historical comparator')
            if old_hash == expected:
                return path
        path = archived.get((name, expected))
        if path is not None:
            check(path, expected)
            return path
        check(name, expected)
        return Path(name)

    def original_receipt_path(item):
        matches = [name for name, digest in archived if digest == item['sha256'] and
                   Path(name).name in {'receipt.json', 'module-receipt.json', 'failure-receipt.json'}]
        require(len(matches) == 1, 'unique exact original receipt path')
        return Path(matches[0])

    def successful(run):
        require(run['exitCode'] == 0 and run['boundedStop'] is None and not run['ownedDescendantsRemaining'],
                'unsuccessful or unclean actual process')
        require(run['wallLimitSeconds'] == 120 and run['cpuLimitSecondsPerProcess'] == 120,
                'actual process bounds')

    def inspect(item, accepted=False):
        record = read(entry(item))
        historical = dict(record.get('historicalComparators', {}))
        # The reused whole-edge compiler receipt names its then-current fixture.
        # Bind that historical name to its exact same-receipt copied input.
        for name, digest in record.get('checks', {}).items():
            if Path(name).name in {'NativeDeclaredWholeEdgeAcceptance.swift', 'NativeDeclaredWholeEdgeAcceptance.py'} and (name, digest) not in archived:
                copied = str(original_receipt_path(item).parent / Path(name).name)
                require(record['checks'].get(copied) == digest and (copied, digest) in archived,
                        'exact copied inherited compiler fixture/runner alias')
                historical[name] = dict(path=str(archived[(copied, digest)]), sha256=digest)
        for field in ['checks', 'selectedProduction', 'freshProduction']:
            for name, digest in record.get(field, {}).items():
                saved_input(name, digest, historical)
        for name, digest in record.get('products', {}).items():
            check(name, digest)
        labels = {}
        for run in record['runs']:
            require(run['label'] not in labels, 'duplicate run label')
            labels[run['label']] = run
            saved_input(str(original_receipt_path(item).parent / (run['label'] + '.log')), run['logSHA256'])
            if accepted:
                successful(run)
        return record, labels, historical

    def selected_payload(item):
        metadata = read(entry(item))
        require(metadata['originalPath'] == str(CURVE) and metadata['currentSHA256'] == CURRENT_CURVE and
                metadata['cachedSHA256'] == CACHED_CURVE, 'selected nominal delta input')
        def method(token):
            start = original.index(token)
            opening = original.index('{', start)
            depth, end = 1, opening + 1
            while depth:
                depth += (original[end] == '{') - (original[end] == '}')
                end += 1
            return start, end
        start = original.index('    private struct TrigonometricPolynomial {')
        end = original.index('    private struct ScalarDifferential {', start)
        pieces = [('actual-nested-helper-declarations', start, end)]
        for token in ['    private static func makeConfiguration(', '    private static func canonicalCone(',
                      '    private static func isNegative(', '    func originalApexReducedSourceSnapshot(']:
            first, after = method(token)
            pieces.append(('actual-new-source-snapshot-port' if token.startswith('    func') else token.strip(), first, after))
        require(len(metadata['ranges']) == len(pieces), 'exact selected helper/port ranges')
        bodies = []
        for item_range, (kind, first, after) in zip(metadata['ranges'], pieces):
            body = original[first:after]
            require(item_range == dict(kind=kind, firstLine=original[:first].count('\n') + 1,
                    lastLine=original[:after].count('\n') + 1,
                    sha256=hashlib.sha256(body.encode()).hexdigest(), bytes=len(body.encode())), 'selected current range bytes')
            bodies.append(body)
        generated = saved_input(metadata['generatedPath'], metadata['generatedSHA256']).read_text()
        header = original[:original.index('public struct CertifiedSphereConeIntersectionCurve:')]
        suffix = header + 'extension CADGeometry.CertifiedSphereConeIntersectionCurve {\n' + bodies[0]
        suffix += ''.join(body + '\n' for body in bodies[1:-1]) + bodies[-1] + '\n}\n'
        require(generated.endswith(suffix) and 'public struct CertifiedSphereConeIntersectionCurve:' not in generated,
                'exact current extension/helper payload without nominal redeclaration')
        return metadata

    for item in nominal['selectedRanges']:
        selected_payload(item)
    require(summary['baselineCommit'] == BASE and summary['productionChanged'] is False and
            summary['publication']['runtimeRepeated'] is False, 'unchanged inputs and no publication replay')
    for key, expected_path in [('summary', whole_summary_path), ('manifest', ROOT / PRIOR.parent / 'manifest.json'),
                               ('integration', ROOT / PRIOR)]:
        require(entry(summary['priorWholeEdge'][key]) == expected_path, 'exact inherited whole-edge metadata')
    require(len(summary['acceptedParts']) == 5, 'exact five accepted parts')
    covered = {lane: set() for lane in LANES}
    accepted = []
    prior_modules = {item['lane']: item for item in whole_summary['compiledBindings']}
    reuse_anchors = read(entry(summary['reusedModuleAnchors']))
    require(set(reuse_anchors) == LANES, 'exact four inherited module anchors')
    for part in summary['acceptedParts']:
        lane, groups = part['lane'], set(part['groups'])
        require(lane in LANES and groups and groups <= GROUPS and not covered[lane].intersection(groups),
                'unique accepted lane/group coverage')
        record, labels, historical = inspect(part['receipt'], accepted=True)
        require(record['cell'] == CELL and record['lane'] == lane and record['success'] is True and
                record['cellComplete'] is False and record['selectedProduction'] == selected and
                record['preAndPostAdmission'] is True and part['rawSuccess'] is True and
                record['state'] == part['rawState'] and set(record['groups']) == groups and
                record['cachedCertifiedCompatibility'] == nominal and part['products'] == record['products'],
                'actual accepted receipt scope and unchanged selected source')
        require(set(labels) == {'compile-link'} | {'runtime-' + group for group in groups},
                'only proof compilation and declared runtime groups; no self/source compilation')
        compact = {item['label']: item for item in part['runs']}
        require(set(compact) == set(labels) and len(compact) == len(part['runs']), 'complete compact run metadata')
        for label, run in labels.items():
            item = compact[label]
            require({key: value for key, value in item.items() if key != 'log'} ==
                    {key: value for key, value in run.items() if key != 'command'} and
                    entry(item['log']).read_bytes() ==
                    saved_input(str(original_receipt_path(part['receipt']).parent / (label + '.log')),
                                run['logSHA256']).read_bytes(), 'exact raw/compact run and log binding')
        command = read(entry(part['assemblyCommand']))
        require(command == labels['compile-link']['command'] and
                'swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc' in command[0] and
                ('Embedded' in command) == (lane == 'embedded') and
                ('-sanitize=address' in command) == (lane == 'asan'), 'actual fixed target compiler/link profile')
        swift_sources = [name for name in command if name.endswith('.swift')]
        require(len(swift_sources) == 1, 'proof compile selects one actual original fixture only')
        selected_fixture = entry(part['fixture'])
        require(record['checks'][swift_sources[0]] == part['fixture']['sha256'] and
                saved_input(swift_sources[0], part['fixture']['sha256'], historical).read_bytes() == selected_fixture.read_bytes(),
                'actual selected fixture version, not inferred current equality')
        runner = entry(part['runner'])
        require(any(Path(name).name == 'NativeIdentityCompositionAcceptance.py' and digest == part['runner']['sha256']
                    for name, digest in record['checks'].items()), 'actual receipt-bound runner version')
        require(runner.read_bytes(), 'nonempty admitted runner')
        reuse = part['reusedSelf4']
        previous_binding = prior_modules[lane]
        require(reuse['selectedProduction4'] == selected and
                reuse['compilerReceipt']['sha256'] == previous_binding['compilerReceipt']['sha256'] and
                reuse['priorWholeEdgeSummary'] == summary['priorWholeEdge']['summary'], 'inherited self4 compiler authority')
        anchor = reuse_anchors[lane]
        require(anchor['sha256'] == reuse['compilerReceipt']['sha256'] and
                anchor['products'] == reuse['products'] and anchor['selectedSource4'] == selected,
                'exact module reuse anchor')
        saved_input(anchor['path'], anchor['sha256'])
        compiler, compiler_labels, compiler_history = inspect(reuse['compilerReceipt'], accepted=True)
        require(compiler['lane'] == lane and compiler['freshProduction'] == selected and
                compiler['products'] == reuse['products'] and set(compiler_labels) == {'compile-self4'} and
                compiler_labels['compile-self4'] == previous_binding['compilerRun'], 'actual existing self4 successful compilation')
        module_command = compiler_labels['compile-self4']['command']
        require(read(entry(previous_binding['command'])) == module_command and
                len([name for name in module_command if name.endswith('.swift')]) == 4, 'four inherited selected compiler bodies')
        for binding in previous_binding['bindings']:
            source, generated = binding['originalPath'], binding['generatedPath']
            require(selected[source] == binding['originalSHA256'] and binding['exactSuffix'] is True and
                    binding['generatedSHA256'] == compiler['checks'][generated] and
                    entry(binding['originalSnapshot']).read_bytes() == Path(source).read_bytes() and
                    entry(binding['generatedSnapshot']).read_bytes() ==
                    b'@testable import NativeDomainAdapters' + bytes([10]) + Path(source).read_bytes(), 'exact existing source/import-prefix contract')
        self_archives = [name for name in compiler['products'] if name.endswith('.a')]
        require(len(self_archives) == 1 and self_archives[0] in command, 'actual reused self4 archive link')
        module_refs = {item['moduleName']: item['receipt'] for item in part['reusedNative32AndSource5']}
        require(set(module_refs) == {'NativeDomainAdapters', 'QuadraticBoundarySources'}, 'unchanged lower module premises')
        for module in record['reusedNative32']:
            ref = module_refs[module['moduleName']]
            require(ref['sha256'] == module['sha256'], 'raw/public retained module receipt')
            lower = read(entry(ref))
            for name, digest in lower['freshProduction'].items():
                check(name, digest)
            for name, digest in lower['products'].items():
                check(name, digest)
        executable = command[command.index('-o') + 1]
        require(executable in record['products'], 'actual proof executable product')
        costs = None
        if 'controls' in groups:
            control = compact['runtime-controls']['log']
            matches = re.findall(r'METRIC preparedQueryBoundary (d+) (d+) (d+)', entry(control).read_text())
            require(len(matches) == 1, 'one actual successful prepared query calibration')
            costs = tuple(int(value) for value in matches[0])
            require(all(value > 0 for value in costs), 'positive actual calibration')
        for group in groups:
            runtime = labels['runtime-' + group]['command']
            require(executable in runtime, 'actual executable runtime')
            argument = group if group in {'complete', 'controls'} else group + ':' + ':'.join(map(str, costs or ()))
            require(runtime[-1] == argument, 'actual runtime group and calibrated work/storage/final callback argument')
            for token in runtime:
                if token.endswith('.mjs') or token == '/usr/local/bin/node':
                    saved_input(token, record['checks'][token], historical)
            if lane == 'embedded':
                log = entry(compact['runtime-' + group]['log']).read_text()
                require('data race detected' not in log and 'was not called on the same actor' not in log,
                        'no rejected actor-isolation runtime warning')
        covered[lane].update(groups)
        accepted.append(part)
    require(all(groups == GROUPS for groups in covered.values()), 'four lanes and all six groups required')
    require(len(summary['diagnostics']) == 1, 'only preserved nonisolated-main compile diagnostic')
    for diagnostic in summary['diagnostics']:
        record, labels, historical = inspect(diagnostic['receipt'])
        require(diagnostic['accepted'] is False and diagnostic['success'] is False and
                diagnostic['runtimeExecuted'] is False and record['success'] is False and
                record['state'] == 'fixture-compile-failed' and set(labels) == {'compile-link'},
                'compile failure remains diagnostic and cannot establish runtime')
        require(read(entry(diagnostic['command'])) == labels['compile-link']['command'] and
                diagnostic['log']['sha256'] == labels['compile-link']['logSHA256'], 'exact diagnostic command/log')
        entry(diagnostic['log'])
        entry(diagnostic['fixture'])
        entry(diagnostic['runner'])

    changed, deleted = {}, []
    for value in git(ROOT, 'diff', '--name-only', '-z', BASE, implementation).split(b'\0'):
        if value:
            relative = value.decode()
            if (ROOT / relative).is_file():
                changed[relative] = sha(ROOT / relative)
            else:
                deleted.append(relative)
    require(not any(name.startswith('Sources/') and not name.endswith('.md') for name in set(changed) | set(deleted)),
            'this cell must not change production inputs')
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
    require(tracked == durable.keys(), 'all new durable CAS/summary/manifest/review entries must be tracked')
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
                  diagnostics=summary['diagnostics'], cachedCertifiedNominal=nominal,
                  inheritedCompilerBindings=prior['inheritedCompilerBindings'], reusedSelf4Bindings=prior_modules,
                  selectedProduction4=selected,
                  freshCompilerSelectedBodies=0, reusedSelf4Bodies=4, rebuiltLowerBodies=0, productionChanged=False,
                  durableEvidence=durable, manifestOriginalReferences=len(manifest['originTuples']),
                  deduplicatedCASFiles=len(manifest['files']), protectedDrafts=protected,
                  auditReferences=references, uniqueArtifacts=len(cache), independentSeconds=independent_seconds,
                  elapsedSeconds=time.monotonic() - started, auditScriptSHA256=sha(__file__),
                  buildOrRuntimeRepeated=False)
    output = ROOT / '.build/native-identity-composition-integration.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['cell', 'implementationCommit', 'mainHead', 'delivered',
                                                 'auditReferences', 'uniqueArtifacts', 'elapsedSeconds']}))


if __name__ == '__main__':
    audit()
