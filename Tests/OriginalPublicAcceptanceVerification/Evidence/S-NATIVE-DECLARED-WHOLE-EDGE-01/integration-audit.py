#!/usr/bin/env python3
"""Check the finite Native whole-edge packet without rebuilding.

The independent checkout may fast-forward to the committed implementation.
Only explicit --deliver may fast-forward the user's clean main checkout.
All accepted groups must bind actual successful compiler/runtime receipts;
diagnostics retain their original status and never count as acceptance.
"""

import argparse
import difflib
import hashlib
import json
import subprocess
import time
from pathlib import Path


ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
INDEPENDENT = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
MAIN = Path('/Users/1amageek/Desktop/3D/swift-CAD')
BASE = 'd59d791bbcb669001cf61144a33745323f29e6dd'
CELL = 'S-NATIVE-DECLARED-WHOLE-EDGE-01'
RELATIVE = Path('Tests/OriginalPublicAcceptanceVerification/Evidence') / CELL
EVIDENCE = ROOT / RELATIVE
PRIOR = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/integration.json')
LANES = {'native', 'asan', 'wasm', 'embedded'}
GROUPS = {'complete', 'controls', 'resources'}
CURVE = ROOT / 'Sources/CADGeometry/CertifiedSphereConeIntersectionCurve.swift'
CURRENT_CURVE = '585f163d5424e7a7ce978469067dcd8c7f24596800d7e1beec62466dafdc8351'
CACHED_CURVE = 'df15cecad78b967d08a07862cc57459d581c5cbe142f1c5915fed8582faca967'
SUMMARY_SHA256 = '9871728c09816b0e7a7946ec11fa930502083dfebf755bcea88cabb127a6f5b5'
MANIFEST_SHA256 = 'f6200e238700b41ba1b78c2b408eb52767b218c7e8fff60d646cd1016f951056'
AUTHORITIES = {
    'fixture': ROOT / 'Tests/OriginalPublicAcceptanceVerification/NativeDeclaredWholeEdgeAcceptance.swift',
    'runner': ROOT / 'Tests/OriginalPublicAcceptanceVerification/NativeDeclaredWholeEdgeAcceptance.py',
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
            'inherited CERT integration differs from baseline')
    require(len(prior['sourcePremises']) == 2170, 'expected inherited 2170 source premises')
    summary_path = arguments.summary.resolve()
    summary_path.relative_to(EVIDENCE)
    require(SUMMARY_SHA256 is not None and MANIFEST_SHA256 is not None, 'final packet hashes are not frozen')
    check(summary_path, SUMMARY_SHA256)
    summary = read(summary_path)
    require(summary['cell'] == CELL and summary['cellComplete'] is False, 'finite cell scope')
    require(set(summary['groups']) == GROUPS and len(summary['groups']) == 3 and
            set(summary['laneSet']) == LANES, 'four lanes and three unique groups required')
    fresh = summary['freshProduction']
    require(len(fresh) == 4 and summary['rebuiltLowerBodies'] == 0, 'four unchanged selected self bodies; no lower rebuild')
    sources = dict(prior['sourcePremises'])
    updates = {}
    for name, digest in fresh.items():
        relative = str(Path(name).relative_to(ROOT / 'Sources'))
        require(sources.get('Sources/' + relative) == digest, 'fresh self body differs from inherited premise')
        check(name, digest)
    for key in ['fixture', 'runner']:
        entry(summary[key])
        check(AUTHORITIES[key], summary[key]['sha256'])
    manifest_path = entry(summary['manifest'])
    require(summary['manifest']['sha256'] == MANIFEST_SHA256, 'frozen final manifest binding')
    manifest = read(manifest_path)
    require(manifest['cell'] == CELL, 'manifest cell')
    archived, durable = {}, {}

    def inherited_text(path, digest):
        relative = str(path.relative_to(ROOT))
        if prior['durableEvidence'].get(relative) == digest:
            return True
        require(relative.startswith('Tests/OriginalPublicAcceptanceVerification/Evidence/'),
                'external historical text must belong to committed acceptance evidence')
        return hashlib.sha256(git(ROOT, 'show', f'{BASE}:{relative}')).hexdigest() == digest

    def register_manifest(record, own=False):
        paths = set()
        for original, item in record['files'].items():
            path = entry(item)
            archived[(original, item['sha256'])] = path
            paths.add(path)
            if own:
                if not path.resolve().is_relative_to(EVIDENCE):
                    require(inherited_text(path, item['sha256']),
                            'external CAS reference must match exact baseline evidence')
                durable[str(path.relative_to(ROOT))] = item['sha256']
        return paths

    cas_paths = register_manifest(manifest, own=True)
    require(len(manifest['files']) == manifest['fileEntries'] and len(cas_paths) == manifest['casFiles'] and
            sum(path.stat().st_size for path in cas_paths) == manifest['casBytes'], 'deduplicated CAS count/bytes')
    for path in [summary_path, manifest_path, EVIDENCE / 'REVIEW.md', EVIDENCE / 'VERIFICATION.md']:
        durable[str(path.relative_to(ROOT))] = sha(path)

    # Prior evidence is referenced, not copied or re-executed. Its exact original
    # path/hash aliases keep cached inputs distinct from current source authority.
    cert_summary_path = ROOT / PRIOR.parent / 'acceptance/summary.json'
    cert_summary_relative = str(cert_summary_path.relative_to(ROOT))
    check(cert_summary_path, prior['durableEvidence'][cert_summary_relative])
    cert_summary = read(cert_summary_path)
    cert_manifest_path = entry(cert_summary['manifest'])
    register_manifest(read(cert_manifest_path))
    nominal = prior['cachedCertifiedNominal']
    require(nominal == cert_summary['cachedCertifiedNominal'] and nominal['originalPath'] == str(CURVE) and
            nominal['currentSHA256'] == CURRENT_CURVE, 'inherited Certified nominal authority')
    original = CURVE.read_text()
    check(CURVE, CURRENT_CURVE)
    port_wrapper = original.rindex('\nextension CertifiedSphereConeIntersectionCurve {')
    cached_bytes = (original[:port_wrapper].rstrip('\n') + '\n').encode()
    cached_path = entry(nominal['cachedBase'])
    require(nominal['cachedBase']['sha256'] == CACHED_CURVE and cached_path.read_bytes() == cached_bytes and
            len(original[port_wrapper:].splitlines()) == 40, 'only the admitted additive port differs from cached nominal')
    archived[(str(CURVE), CACHED_CURVE)] = cached_path

    def saved_input(name, expected, comparators=None):
        comparator = (comparators or {}).get(name)
        if comparator is not None:
            historical_hash = comparator['sha256']
            path = archived.get((comparator['path'], historical_hash))
            path = path if path is not None else entry(comparator)
            check(path, historical_hash)
            require(path in archived.values() or inherited_text(path, historical_hash),
                    'historical comparator must already be durable evidence')
            if historical_hash == expected:
                return path
        historical = archived.get((name, expected))
        if historical is not None:
            check(historical, expected)
            return historical
        check(name, expected)
        return Path(name)

    def successful(run, label):
        require(run['label'] == label and run['exitCode'] == 0 and run['boundedStop'] is None and
                not run['ownedDescendantsRemaining'], f'unsuccessful or unclean run: {label}')
        require(run['wallLimitSeconds'] == 120 and run['cpuLimitSecondsPerProcess'] == 120,
                f'actual bounded process contract: {label}')

    def original_receipt_path(item):
        matches = [name for name, digest in archived if digest == item['sha256'] and
                   Path(name).name in {'receipt.json', 'module-receipt.json', 'failure-receipt.json'}]
        require(len(matches) == 1, f'exact original receipt path: {item["path"]}')
        return Path(matches[0])

    def inspect(item, accepted=False):
        record = read(entry(item))
        historical = dict(record.get('historicalComparators', {}))
        for authority in ['fixture', 'runner']:
            name = str(AUTHORITIES[authority])
            digest = record['checks'].get(name)
            if digest is not None and digest != summary[authority]['sha256']:
                copied = str(original_receipt_path(item).parent / Path(name).name)
                require(record['checks'].get(copied) == digest and (copied, digest) in archived,
                        f'exact copied historical {authority} binding')
                historical[name] = dict(path=str(archived[(copied, digest)]), sha256=digest)
        for field in ['checks', 'freshProduction']:
            for name, digest in record.get(field, {}).items():
                saved_input(name, digest, historical)
        for name, digest in record.get('products', {}).items():
            check(name, digest)
        labels = {}
        for run in record['runs']:
            label = run['label']
            require(label not in labels, 'duplicate run label')
            labels[label] = run
            saved_input(str(original_receipt_path(item).parent / (label + '.log')), run['logSHA256'])
            if accepted:
                successful(run, label)
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
    require(summary['cachedCertifiedNominal'] == nominal, 'final packet preserves inherited nominal delta')
    compatibility = summary['fixtureOutputCompatibility']
    before = entry(compatibility['before']).read_text()
    after = entry(compatibility['after']).read_text()
    recorded_diff = entry(compatibility['diff']).read_text()
    require(compatibility['runtimeRepeated'] is False and
            recorded_diff == ''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                fromfile='accepted-native-v4-fixture', tofile='final-embedded-v2-fixture')),
            'exact output-only fixture compatibility snapshot/diff')
    entry_compatibility = summary['fixtureEntryCompatibility']
    entry_before = entry(entry_compatibility['before']).read_text()
    entry_after = entry(entry_compatibility['after']).read_text()
    require(entry_compatibility['finding'] == 'F1' and
            entry_compatibility['before']['sha256'] == compatibility['after']['sha256'] and
            entry_compatibility['after'] == summary['fixture'] and
            entry_compatibility['replayedTargets'] == ['embedded'] and
            entry_compatibility['reusedSelf4'] is True and entry_compatibility['warningAbsent'] is True and
            entry(entry_compatibility['diff']).read_text() == ''.join(difflib.unified_diff(
                entry_before.splitlines(True), entry_after.splitlines(True),
                fromfile='embedded-v2-rejected-isolation-entry', tofile='embedded-v3-callback-free-entry')),
            'exact F1 callback-free entry correction distinct from output compatibility')
    compiled_bindings = {item['lane']: item for item in summary['compiledBindings']}
    require(set(compiled_bindings) == LANES and len(summary['compiledBindings']) == 4,
            'one actual compiler binding per lane')
    covered = {lane: set() for lane in LANES}
    accepted = []
    for part in summary['accepted']:
        lane = part['lane']
        groups = set(part['groups'])
        require(lane in LANES and groups and groups <= GROUPS and not covered[lane].intersection(groups),
                'accepted lane/group duplication')
        record, labels, historical = inspect(part['receipt'], accepted=True)
        require(record['cell'] == CELL and record['lane'] == lane and record['success'] is True and
                record['cellComplete'] is False and record['freshProduction'] == fresh and
                record['preAndPostAdmission'] is True and part['rawSuccess'] is True and
                part['rawState'] == record['state'], 'accepted raw receipt/current premise binding')
        require(part['products'] == record['products'] and part['runs'] == record['runs'], 'summary raw products/runs')
        require(part['historicalComparators'] == record['historicalComparators'], 'exact historical alias metadata')
        require(record['cachedCertifiedCompatibility'] == nominal, 'cached nominal delta was not preserved')
        group_labels = part['groupRunLabels']
        require(set(group_labels) == groups and set(part['successRunLabels']) == set(group_labels.values()),
                'explicit accepted group/run labels')
        for group, label in group_labels.items():
            require(label in {'runtime-' + group, 'runtime-all'} and label in labels, 'actual selected runtime group')
        command = read(entry(part['assemblyCommand']))
        require('compile-link' in labels and command == labels['compile-link']['command'], 'actual compiler/link command')
        require('swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc' in command[0] and
                ('Embedded' in command) == (lane == 'embedded') and
                ('-sanitize=address' in command) == (lane == 'asan'), 'fixed target/compiler mode')
        compiler, compiler_labels, compiler_history = inspect(part['compilerReceipt'], accepted=True)
        require(compiler['lane'] == lane and compiler['freshProduction'] == fresh and
                set(compiler_labels) == {'compile-self4'}, 'actual unchanged self4 compiler receipt')
        binding = compiled_bindings[lane]
        module_command = compiler_labels['compile-self4']['command']
        require(binding['compilerReceipt'] == part['compilerReceipt'] and binding['selectedBodies'] == 4 and
                binding['compilerRun'] == compiler_labels['compile-self4'] and
                read(entry(binding['command'])) == module_command and len(binding['bindings']) == 4,
                'summary compiler source/run/command bindings')
        saved_command_name = str(original_receipt_path(part['compilerReceipt']).parent / 'compile-self4.json')
        saved_commands = [path for (name, _), path in archived.items() if name == saved_command_name]
        require(len(saved_commands) == 1 and read(saved_commands[0]) == module_command,
                'saved actual self4 compiler command')
        require('swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc' in module_command[0] and
                ('Embedded' in module_command) == (lane == 'embedded') and
                ('-sanitize=address' in module_command) == (lane == 'asan'), 'self4 compiler/target profile')
        generated = [name for name in module_command if name.endswith('.swift')]
        require(len(generated) == 4 and {Path(name).name for name in generated} ==
                {Path(name).name for name in fresh}, 'four actual selected unchanged self bodies')
        for name in generated:
            source = next(path for path in fresh if Path(path).name == Path(name).name)
            body = saved_input(name, compiler['checks'][name], compiler_history).read_bytes()
            require(body == b'@testable import NativeDomainAdapters\n' + Path(source).read_bytes(),
                    'exact current source body with only admitted nominal import prefix')
            source_bindings = [item for item in binding['bindings'] if item['originalPath'] == source]
            require(len(source_bindings) == 1, 'exact source binding')
            source_binding = source_bindings[0]
            require(source_binding['originalSHA256'] == fresh[source] and source_binding['generatedPath'] == name and
                    source_binding['generatedSHA256'] == compiler['checks'][name] and
                    source_binding['prefixSHA256'] == hashlib.sha256(b'@testable import NativeDomainAdapters\n').hexdigest() and
                    source_binding['exactSuffix'] is True and
                    entry(source_binding['originalSnapshot']).read_bytes() == Path(source).read_bytes() and
                    entry(source_binding['generatedSnapshot']).read_bytes() == body,
                    'exact source snapshot and generated import prefix metadata')
        archives = [name for name in compiler['products'] if name.endswith('.a')]
        require(len(archives) == 1 and archives[0] in command, 'proof must link its admitted self module')
        native_archives = [name for name in command if name.endswith('/libNativeDomainAdapters.a')]
        require(len(native_archives) == 1, 'proof must link the admitted Native32 owner')
        native_modules = [module for module in record['reusedNative32'] if module['moduleName'] == 'NativeDomainAdapters']
        require(len(native_modules) == 1, 'explicit reused Native32 module receipt')
        native_module_ref = native_modules[0]
        native_base = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01'
        native_path = Path(native_module_ref['receipt'])
        native_path = native_path if native_path.is_absolute() else native_base / native_path
        saved_input(str(native_path), native_module_ref['sha256'], historical)
        native_module = read(native_path)
        require(len(native_module['freshProduction']) == 32 and
                native_module['products'].get(native_archives[0]) == record['checks'].get(native_archives[0], record['products'].get(native_archives[0])),
                'actual reused Native32 archive/source receipt binding')
        for name, digest in native_module['freshProduction'].items():
            check(name, digest)
        fixture_original = str(AUTHORITIES['fixture'])
        fixture_digest = record['checks'][fixture_original]
        fixture_bytes = saved_input(fixture_original, fixture_digest, historical).read_bytes()
        selected_swift = [name for name in command if name.endswith('.swift')]
        require(selected_swift == [fixture_original] and fixture_bytes,
                'actual proof command selects exactly its receipt-bound fixture')
        executable = command[command.index('-o') + 1]
        require(executable in record['products'], 'actual compiled executable product')
        for label in set(group_labels.values()):
            runtime = labels[label]['command']
            require(executable in runtime and runtime[-1] == label.removeprefix('runtime-'),
                    'actual executable/group runtime binding')
            for token in runtime:
                if token.endswith('.mjs') or token == '/usr/local/bin/node':
                    saved_input(token, record['checks'][token], historical)
        if lane == 'embedded':
            require(part['version'] == 'v3' and part['receipt']['sha256'] ==
                    '16b981c743b02a6337f6d2c4440b130d0a72e9acff76a557c4f9d99253cd1ac4',
                    'only F1-corrected Embedded v3 is accepted')
            require(summary['embeddedObservation']['acceptedReceipt'] == part['receipt'] and
                    summary['embeddedObservation']['warningAbsentInAccepted'] is True,
                    'corrected Embedded receipt binding')
            runtime = labels['runtime-all']
            require(runtime['logSHA256'] == 'c2dbb0e1efb43b67c64e8f930561a65b622a88665741a616af1c64df9cc83dbf',
                    'F1 corrected runtime log')
            log = saved_input(str(original_receipt_path(part['receipt']).parent / 'runtime-all.log'),
                              runtime['logSHA256']).read_text()
            require('data race detected' not in log and 'was not called on the same actor' not in log,
                    'accepted Embedded entry must not emit the rejected F1 warning')
        covered[lane].update(groups)
        accepted.append(part)
    require(all(groups == GROUPS for groups in covered.values()), 'four-lane three-group coverage incomplete')
    for diagnostic in summary['diagnostics']:
        require(bool(diagnostic['scope']), 'diagnostic scope required')
        record = read(entry(diagnostic['receipt']))
        require(record['state'] == diagnostic['rawState'] and
                record['success'] == diagnostic['rawSuccess'] and diagnostic['acceptedAsWholeRun'] is False,
                'diagnostic raw state must not count as acceptance')
        if record['success']:
            require(diagnostic['receipt']['sha256'] ==
                    'b6bd5c1f38376810a53fed9e7a0b50450012e9606495935f7788a3a05c0e2eee' and
                    diagnostic['lane'] == 'embedded' and diagnostic['version'] == 'v2' and
                    diagnostic['acceptanceRejected'] is True and diagnostic['rejectionFinding'] == 'F1' and
                    summary['embeddedObservation']['rejectedReceipt'] == diagnostic['receipt'],
                    'only exact preserved Embedded v2 exit-zero F1 rejection is a successful diagnostic')
        else:
            require(diagnostic['rawSuccess'] is False, 'failed diagnostic raw status unchanged')
        for run in record['runs']:
            saved_input(str(original_receipt_path(diagnostic['receipt']).parent / (run['label'] + '.log')), run['logSHA256'])

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
                  inheritedCompilerBindings=prior['compilerBindings'], freshProduction=fresh,
                  compilerSelectedBodies=4, rebuiltLowerBodies=0, productionChanged=False,
                  durableEvidence=durable, manifestOriginalReferences=len(manifest['files']),
                  deduplicatedCASFiles=len(cas_paths), protectedDrafts=protected,
                  auditReferences=references, uniqueArtifacts=len(cache), independentSeconds=independent_seconds,
                  elapsedSeconds=time.monotonic() - started, auditScriptSHA256=sha(__file__),
                  buildOrRuntimeRepeated=False)
    output = ROOT / '.build/native-declared-whole-edge-integration.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['cell', 'implementationCommit', 'mainHead', 'delivered',
                                                 'auditReferences', 'uniqueArtifacts', 'elapsedSeconds']}))


if __name__ == '__main__':
    audit()
