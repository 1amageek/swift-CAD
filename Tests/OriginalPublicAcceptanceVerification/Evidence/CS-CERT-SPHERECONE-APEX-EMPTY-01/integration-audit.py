#!/usr/bin/env python3
"""Check the finite certified-apex packet without rebuilding.

The independent checkout may fast-forward to the committed implementation.
Only explicit --deliver may fast-forward the user's clean main checkout.
All accepted groups must bind actual successful compiler/runtime receipts;
diagnostics retain their original status and never count as acceptance.
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
BASE = 'b3a48f078f682e87b969f18f524f47d4ad0c67d7'
CELL = 'CS-CERT-SPHERECONE-APEX-EMPTY-01'
RELATIVE = Path('Tests/OriginalPublicAcceptanceVerification/Evidence') / CELL
EVIDENCE = ROOT / RELATIVE
PRIOR = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/CS-ANGULAR-PHYSICAL-ARC-PLANE-01/integration.json')
LANES = {'native', 'asan', 'wasm', 'embedded'}
GROUPS = {'complete', 'dispatch', 'source', 'requests', 'resources', 'readmission',
          'cancel-entry', 'cancel-final', 'cancel-reader', 'lifetime'}
CURVE = ROOT / 'Sources/CADGeometry/CertifiedSphereConeIntersectionCurve.swift'
CURRENT_CURVE = '585f163d5424e7a7ce978469067dcd8c7f24596800d7e1beec62466dafdc8351'
CACHED_CURVE = 'df15cecad78b967d08a07862cc57459d581c5cbe142f1c5915fed8582faca967'
SUMMARY_SHA256 = 'bec8cfd5451bfd3ffc4b79b8eecf5ffdd098d792fc34590028a110fe29999fca'
MANIFEST_SHA256 = '15cb054081968054acd132579e94576a359a616a3c7b87c36a67ad0a1f63d9d8'


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
    parser.add_argument('--summary', type=Path, default=EVIDENCE / 'acceptance/summary.json')
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
            'inherited Angular integration differs from baseline')
    require(len(prior['sourcePremises']) == 2160, 'expected inherited 2160 source premises')
    summary_path = arguments.summary.resolve()
    summary_path.relative_to(EVIDENCE)
    check(summary_path, SUMMARY_SHA256)
    summary = read(summary_path)
    require(summary['cell'] == CELL and summary['cellComplete'] is False and
            summary['deliveryPending'] is True, 'finite cell/pending-delivery scope')
    require(set(summary['laneSet']) == LANES and set(summary['groups']) == GROUPS and
            len(summary['groups']) == 10, 'four lanes and ten unique groups required')
    fresh = summary['freshProduction']
    require(len(fresh) == 47 and summary['sourceBodies'] == 6 and summary['upperBodies'] == 41 and
            summary['rebuiltLowerBodies'] == 0, 'expected selected 47 bodies and no lower rebuild')
    for name, digest in fresh.items():
        Path(name).relative_to(ROOT / 'Sources')
        check(name, digest)
    for key in ['fixture', 'runner']:
        check(summary[key]['path'], summary[key]['sha256'])

    manifest_path = entry(summary['manifest'])
    require(summary['manifest']['sha256'] == MANIFEST_SHA256, 'frozen final manifest binding')
    manifest = read(manifest_path)
    require(manifest['cell'] == CELL, 'manifest cell')
    archived = {}
    durable = {}
    for original, item in manifest['files'].items():
        path = entry(item)
        path.resolve().relative_to(EVIDENCE)
        archived[(original, item['sha256'])] = path
        durable[str(path.relative_to(ROOT))] = item['sha256']
    require(len(manifest['files']) == manifest['fileEntries'], 'manifest entry count')
    cas_paths = set(archived.values())
    require(len(cas_paths) == manifest['casFiles'] and
            sum(path.stat().st_size for path in cas_paths) == manifest['casBytes'], 'deduplicated CAS count/bytes')
    for path in [summary_path, manifest_path, EVIDENCE / 'REVIEW.md', EVIDENCE / 'acceptance/VERIFICATION.md']:
        durable[str(path.relative_to(ROOT))] = sha(path)

    nominal = summary['cachedCertifiedNominal']
    require(nominal['originalPath'] == str(CURVE) and nominal['currentSHA256'] == CURRENT_CURVE and
            fresh[str(CURVE)] == CURRENT_CURVE, 'current Certified nominal binding')
    original = CURVE.read_text()
    port_wrapper = original.rindex('\nextension CertifiedSphereConeIntersectionCurve {')
    cached_bytes = (original[:port_wrapper].rstrip('\n') + '\n').encode()
    cached_path = entry(nominal['cachedBase'])
    require(nominal['cachedBase']['sha256'] == CACHED_CURVE and cached_path.read_bytes() == cached_bytes,
            'cached declaration/storage/constructor bytes differ beyond additive port')
    require(len(original[port_wrapper:].splitlines()) == 40,
            'only the frozen 40-line additive source port may differ')
    archived[(str(CURVE), CACHED_CURVE)] = cached_path

    def saved_input(name, expected):
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
                f'actual process bound: {label}')

    def receipt_original_path(item):
        matches = [name for name, digest in archived if digest == item['sha256'] and
                   Path(name).name in {'receipt.json', 'source-receipt.json'}]
        require(len(matches) == 1, f'exact original receipt path: {item["path"]}')
        return Path(matches[0])

    def run_log(item, run):
        log_name = str(receipt_original_path(item).parent / (run['label'] + '.log'))
        return saved_input(log_name, run['logSHA256'])

    def inspect(item, accepted=False):
        receipt_path = entry(item)
        record = read(receipt_path)
        # A prior selected fixture/runner is bound to its exact copied input in
        # the same receipt, never asserted equal to the current source path.
        for authority in ['fixture', 'runner']:
            name = summary[authority]['path']
            digest = record.get('checks', {}).get(name)
            if digest is not None and digest != summary[authority]['sha256']:
                copied = str(receipt_original_path(item).parent / Path(name).name)
                require(record['checks'].get(copied) == digest and (copied, digest) in archived,
                        f'exact copied historical {authority} binding')
                archived[(name, digest)] = archived[(copied, digest)]
        for field in ['checks', 'freshProduction']:
            for name, digest in record.get(field, {}).items():
                saved_input(name, digest)
        for name, digest in record.get('products', {}).items():
            check(name, digest)
        labels = {}
        for run in record['runs']:
            label = run['label']
            require(label not in labels, f'duplicate run label: {receipt_path}: {label}')
            labels[label] = run
            check(run_log(item, run), run['logSHA256'])
            if accepted:
                successful(run, label)
        return record, labels

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

    def compiler_profile(command, lane):
        require('swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc' in command[0], 'fixed release compiler')
        require(command[command.index('-num-threads') + 1] == '2', 'actual compiler threads')
        target = command[command.index('-target') + 1]
        sdk = command[command.index('-sdk') + 1]
        features = [command[i + 1] for i in range(len(command) - 1)
                    if command[i] == '-enable-experimental-feature']
        require(('Embedded' in features) == (lane == 'embedded'), 'Embedded compiler mode binding')
        if lane in {'native', 'asan'}:
            require(target == 'arm64-apple-macos15.0' and sdk.endswith('/MacOSX27.0.sdk'), 'Native target/SDK')
            require(('-sanitize=address' in command) == (lane == 'asan'), 'ASAN compiler mode')
        else:
            require(target == 'wasm32-unknown-wasip1' and '/swift-6.4.0-RELEASE_wasm.artifactbundle/' in sdk,
                    'matching release WebAssembly SDK')
            resource = command[command.index('-resource-dir') + 1]
            require(resource.endswith('/usr/lib/swift' if lane == 'embedded' else '/usr/lib/swift_static'),
                    'actual portable runtime resource directory')

    def fixture_equivalence(old_path, selected_groups):
        before = old_path.read_text()
        after = Path(summary['fixture']['path']).read_text()
        require('snapshot.halfAngle.bitPattern == 0x3fddac670561bb50' in before and
                'f.originalRadians.bitPattern == snapshot.halfAngle.bitPattern' in before,
                'historical successful oracle must have checked the same authored input bits')
        require('readmission' not in selected_groups, 'changed readmission requires its final fixture run')
        added = ('    // Exact authored binary input recorded by the independent source worksheet.\n'
                 '    static let authoredHalfAngle = Double(bitPattern: 0x3fddac670561bb50)\n')
        require(after.count(added) == 1 and before.count('atan(0.5)') == 4, 'exact fixture input-bit delta')
        before = before.replace('atan(0.5)', 'authoredHalfAngle')
        after = after.replace(added, '')
        first = '        } else if group == "readmission" {'
        last = '        } else if group == "cancel-entry" {'
        def omit_changed_readmission(text):
            start = text.index(first)
            end = text.index(last, start)
            return text[:start] + text[end:]
        require(omit_changed_readmission(before) == omit_changed_readmission(after),
                'selected historical fixture groups differ beyond the declared identical-input substitution')

    bindings = summary['compiledBindings']
    require(len(bindings) == 46 and {item['originalPath'] for item in bindings} == set(fresh) - {str(CURVE)},
            'all other 46 compiled source bindings required')
    for binding in bindings:
        name = binding['originalPath']
        original_bytes = entry(binding['original']).read_bytes()
        compiled = entry(binding['compiledInput']).read_bytes()
        require(binding['original']['sha256'] == fresh[name] and compiled.endswith(original_bytes) and
                hashlib.sha256(compiled[:-len(original_bytes)]).hexdigest() == binding['prefixSHA256'],
                'exact original source suffix and import prefix')

    covered = {lane: set() for lane in LANES}
    accepted = []
    for part in summary['accepted']:
        lane = part['lane']
        selected_groups = set(part['groups'])
        require(lane in LANES and selected_groups and not covered[lane].intersection(selected_groups),
                'accepted group duplication or unknown lane')
        record, labels = inspect(part['receipt'], accepted=True)
        require(record['cell'] == CELL and record['lane'] == lane and record['success'] is True and
                record['cellComplete'] is False and record['postHashesMatch'] is True and
                record['freshProduction'] == fresh and record['rebuiltLowerBodies'] == 0,
                'accepted receipt status/current47 scope')
        require(part['rawSuccess'] is True and part['rawState'] == record['state'] and
                part['preAndPostAdmissionPassed'] is True and selected_groups <= set(record['groups']), 'accepted raw status binding')
        required_runs = {'runtime-' + group for group in selected_groups}
        require(set(part['successRunLabels']) == required_runs and required_runs <= labels.keys(), 'exact selected success labels')
        require(part['runs'] == record['runs'] and part['products'] == record['products'], 'summary raw run/product binding')
        module, module_labels = inspect(part['sourceModuleReceipt'], accepted=True)
        require(module['lane'] == lane and len(module['freshProduction']) == 6 and
                all(fresh.get(name) == digest for name, digest in module['freshProduction'].items()) and
                set(module_labels) == {'compile-source'}, 'actual six-body source module')
        module_command = module_labels['compile-source']['command']
        compiler_profile(module_command, lane)
        source_command_path = str(receipt_original_path(part['sourceModuleReceipt']).parent / 'source-command.json')
        source_commands = [path for (name, _), path in archived.items() if name == source_command_path]
        require(len(source_commands) == 1 and read(source_commands[0]) == module_command,
                'saved actual source compiler command binding')
        module_inputs = [name for name in module_command if name.endswith('.swift')]
        require(len(module_inputs) == 6, 'source module actual compiler body count')
        assembly_command = read(entry(part['assemblyCommand']))
        if 'reusedAssembly' in part:
            reused = read(entry(part['reusedAssembly']))
            previous_path = saved_input(reused['receipt'], reused['sha256'])
            previous, previous_labels = inspect(dict(path=str(previous_path), sha256=reused['sha256']), accepted=True)
            require(reused['freshProduction'] == fresh and previous['freshProduction'] == fresh and
                    previous['products'].get(reused['product']) == reused['productSHA256'] and
                    record['products'].get(reused['product']) == reused['productSHA256'], 'reused actual assembly product')
            compiler = previous_labels['compile-link']
        else:
            compiler = labels['compile-link']
        require(compiler['command'] == assembly_command, 'actual successful compiler command binding')
        compiler_profile(assembly_command, lane)
        upper_inputs = [name for name in assembly_command if name.endswith('.swift') and '/upper/' in name]
        require(len(upper_inputs) == 41 and {Path(name).name for name in upper_inputs} ==
                {Path(name).name for name in fresh if name not in module['freshProduction']}, 'actual 41 upper compiler bodies')
        archives = [name for name in module['products'] if name.endswith('.a')]
        require(len(archives) == 1 and archives[0] in assembly_command, 'linked admitted source archive')
        executable = assembly_command[assembly_command.index('-o') + 1]
        require(executable in record['products'], 'compile output must be accepted runtime product')
        for label in required_runs:
            command = labels[label]['command']
            require(executable in command and command[-1] == label.removeprefix('runtime-'),
                    f'actual runtime executable/group binding: {label}')
            for token in command:
                if token.endswith('.mjs') or token == '/usr/local/bin/node':
                    saved_input(token, record['checks'][token])
        for compiled_name in module_inputs + upper_inputs:
            checks = module['checks'] if compiled_name in module_inputs else record['checks']
            compiled_bytes = saved_input(compiled_name, checks[compiled_name]).read_bytes()
            if Path(compiled_name).name == 'CertifiedApexSourcePayload.swift':
                continue
            candidates = [name for name in fresh if Path(name).name == Path(compiled_name).name]
            require(len(candidates) == 1 and compiled_bytes.endswith(Path(candidates[0]).read_bytes()),
                    'each actual lane compiler input must retain its current original body')
        payload = selected_payload(part['generatedSourceRanges'])
        payload_inputs = [name for name in module_inputs if Path(name).name == 'CertifiedApexSourcePayload.swift']
        require(len(payload_inputs) == 1 and module['checks'][payload_inputs[0]] == payload['generatedSHA256'],
                'actual reused/fresh source module compiled the selected current nominal payload')
        archived_fixture = entry(part['exactFixture'])
        proof_inputs = [name for name in assembly_command if Path(name).name == 'Proof.swift']
        require(len(proof_inputs) == 1 and
                saved_input(proof_inputs[0], record['checks'][proof_inputs[0]]).read_bytes().endswith(archived_fixture.read_bytes()),
                'actual compiled Proof must contain its exact admitted fixture')
        if sha(archived_fixture) != summary['fixture']['sha256']:
            comparator = part['fixtureComparator']
            require(entry(comparator['old']) == archived_fixture and
                    comparator['current']['sha256'] == summary['fixture']['sha256'] and
                    'readmission' not in selected_groups, 'historical fixture has only explicitly selected unchanged groups')
            entry(comparator['current'])
            fixture_equivalence(archived_fixture, selected_groups)
        covered[lane].update(selected_groups)
        accepted.append(part)
    require(all(value == GROUPS for value in covered.values()), 'four-lane ten-group coverage incomplete')

    for item in summary['cachedCertifiedNominal']['selectedRanges']:
        selected_payload(item)
    for diagnostic in summary['diagnostics']:
        require(bool(diagnostic['scope']) and diagnostic['rawSuccess'] is False, 'diagnostic classification')
        record = read(entry(diagnostic['receipt']))
        require(record['success'] is False and record['state'] == diagnostic['rawState'] and
                record['runs'] == diagnostic['runs'], 'diagnostic raw state must not be relabeled')
        for run in record['runs']:
            check(run_log(diagnostic['receipt'], run), run['logSHA256'])
    entry(summary['diagnosticFirstThrow'])
    check(summary['originalObservation']['path'], summary['originalObservation']['sha256'])
    for lower in summary['retainedLowerEvidence']:
        check(lower['path'], lower['sha256'])

    sources = dict(prior['sourcePremises'])
    updates = {}
    for name, digest in fresh.items():
        relative = str(Path(name).relative_to(ROOT))
        if sources.get(relative) != digest:
            updates[relative] = {'before': sources.get(relative), 'after': digest}
        sources[relative] = digest
    existing_newly_indexed = ['Sources/CADGeometry/DefaultSurfaceSurfaceIntersector.swift',
                             'Sources/CADGeometry/PlanePlaneSurfaceIntersector.swift']
    for relative in existing_newly_indexed:
        require(updates[relative]['before'] is None and
                hashlib.sha256(git(ROOT, 'show', f'{BASE}:{relative}')).hexdigest() == sources[relative],
                'newly indexed SSI/PlanePlane body must equal baseline main')
    require(len(updates) == 14 and sum(item['before'] is None for item in updates.values()) == 10 and
            len(sources) == 2170, 'expected 12 changed bodies, two unchanged newly indexed bodies, 2170 premises')
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
    require(tracked == durable.keys(), 'all durable CAS/summary/manifest/review entries must be tracked')
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
                  diagnostics=summary['diagnostics'], cachedCertifiedNominal=nominal, compilerBindings=bindings,
                  compilerSelectedBodies=47, sourceBodies=6, upperBodies=41, rebuiltLowerBodies=0,
                  durableEvidence=durable, manifestOriginalReferences=len(manifest['files']),
                  deduplicatedCASFiles=len(cas_paths), protectedDrafts=protected,
                  auditReferences=references, uniqueArtifacts=len(cache), independentSeconds=independent_seconds,
                  elapsedSeconds=time.monotonic() - started, auditScriptSHA256=sha(__file__),
                  buildOrRuntimeRepeated=False)
    output = ROOT / '.build/cert-apex-integration.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['cell', 'implementationCommit', 'mainHead', 'delivered',
                                                 'auditReferences', 'uniqueArtifacts', 'elapsedSeconds']}))


if __name__ == '__main__':
    audit()
