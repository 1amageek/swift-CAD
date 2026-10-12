#!/usr/bin/env python3
"""Read-only delivery audit for the finite implicit public cell.

Root prepares committed root and independent checkouts; main stays at baseline. This audit
never builds, executes a cached product, changes Git or regenerates evidence.
Frozen packet and review hashes are mandatory caller inputs. Missing evidence,
unknown historical comparators and incomplete selected-body bindings fail closed.
"""

import argparse
import hashlib
import json
import shlex
import subprocess
import time
from pathlib import Path

ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
INDEPENDENT = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
MAIN = Path('/Users/1amageek/Desktop/3D/swift-CAD')
CELL = 'CS-IMPLICIT-DYADIC-PARABOLA-PLANE-01'
RELATIVE = Path('Tests/OriginalPublicAcceptanceVerification/Evidence') / CELL
EVIDENCE = ROOT / RELATIVE
PRIOR = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/CS-CERT-SPHERECONE-APEX-EMPTY-01/integration.json')
LANES = {'native', 'asan', 'wasm', 'embedded'}
GROUPS = {'ordinary', 'source', 'selections', 'continuous', 'limits', 'budgets',
          'cancel-entry', 'cancel-mid', 'cancel-final', 'cancel-empty', 'lifetime'}
SOURCE_NAMES = {
    'OriginalImplicitCurveSnapshot.swift', 'OriginalImplicitCurveSnapshotProvider.swift',
    'OriginalImplicitCurveGraphEvidence.swift', 'OriginalImplicitCurveGraphReduction.swift',
    'DefaultOriginalFiniteImplicitCurveGraphPreparer.swift',
}
DRAFT_NAMES = {'OriginalDraftedZeroLinePublicProducer.swift', 'OriginalRationalGraphPointPublisher.swift'}
CACHED_NAMES = {
    'CertifiedImplicitIntersectionCurve.swift', 'CertifiedImplicitIntersectionGraphCell.swift',
    'DefaultCertifiedImplicitCurveAnalyticSurfaceIntersector.swift', 'ImplicitCurveIntervalJetEncloser.swift',
    'CertifiedImplicitCurveAnalyticSurfaceIntersecting.swift', 'SurfaceIntersectionParameterBox.swift',
    'SurfaceIntersectionParameterPair.swift', 'Curve3D.swift', 'ExactAffineBSplineSurfacePatch.swift',
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
    parser.add_argument('--baseline', required=True, help='latest main SHA before this delivery')
    parser.add_argument('--summary-sha256')
    parser.add_argument('--manifest-sha256')
    parser.add_argument('--review-sha256')
    parser.add_argument('--post-delivery-receipt', type=Path)
    parser.add_argument('--post-delivery-receipt-sha256')
    parser.add_argument('--summary', type=Path, default=EVIDENCE / 'acceptance/summary.json')
    args = parser.parse_args()
    started = time.monotonic()
    cache, references = {}, 0

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
        require(len(expected) == 64 and sha(path) == expected, f'SHA mismatch: {path}')
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

    def exact_head(directory, expected=None):
        require(git(directory, 'rev-parse', 'HEAD').decode().strip() == (expected or args.implementation),
                f'checkout must already be at committed implementation: {directory}')
        require(not git(directory, 'status', '--porcelain=v1', '-z'), f'dirty checkout: {directory}')

    for commit in [args.implementation, args.baseline]:
        require(git(ROOT, 'rev-parse', commit).decode().strip() == commit, 'full commit SHA required')
    require(args.baseline != args.implementation, 'delivery baseline must precede implementation')
    subprocess.run(['git', 'merge-base', '--is-ancestor', args.baseline, args.implementation],
                   cwd=ROOT, check=True, timeout=30)
    for directory in [ROOT, INDEPENDENT]:
        exact_head(directory)
    require(git(MAIN, 'branch', '--show-current').decode().strip() == 'main', 'main branch required')
    implementation_tree = git(ROOT, 'rev-parse', args.implementation + '^{tree}').decode().strip()

    def protected_metadata(protected):
        for name, directory in [('source', '/private/tmp/cad-di-m4-source-support-20261009'),
                                ('consumer', '/private/tmp/cad-di-m6-consumers-20261009')]:
            directory, record = Path(directory), protected[name]
            require(len(record['files']) == (18 if name == 'source' else 264), 'protected source/consumer count')
            require(git(directory, 'rev-parse', 'HEAD').decode().strip() == record['head'], 'protected HEAD')
            index = Path(git(directory, 'rev-parse', '--git-path', 'index').decode().strip())
            check(index if index.is_absolute() else directory / index, record['indexSHA256'])
            require(hashlib.sha256(git(directory, 'status', '--porcelain=v1', '-z')).hexdigest() ==
                    record['statusSHA256'], 'protected status')
        check('/Users/1amageek/.codex/worktrees/source-consumer-handoff-recovery/pending-public-publisher.patch',
              protected['patchSHA256'])

    if args.post_delivery_receipt:
        require(args.post_delivery_receipt_sha256, 'post-delivery requires frozen pre-delivery receipt SHA')
        check(args.post_delivery_receipt, args.post_delivery_receipt_sha256)
        previous = read(args.post_delivery_receipt)
        require(previous['cell'] == CELL and previous['implementationCommit'] == args.implementation and
                previous['mainBefore'] == args.baseline and previous['delivered'] is False and
                previous['implementationTree'] == implementation_tree and
                previous['auditScriptSHA256'] == sha(__file__), 'exact successful pre-delivery audit binding')
        for directory in [ROOT, INDEPENDENT, MAIN]:
            exact_head(directory)
            require(git(directory, 'rev-parse', 'HEAD^{tree}').decode().strip() == implementation_tree,
                    'post-delivery tree differs from audited implementation')
        protected_metadata(previous['protectedDrafts'])
        previous.update(delivered=True, mainHead=args.implementation,
                        postDeliveryAudit=dict(receipt=str(args.post_delivery_receipt),
                            receiptSHA256=args.post_delivery_receipt_sha256,
                            implementationTree=implementation_tree, cleanCheckouts=True,
                            protectedMetadataUnchanged=True, lowerOrEvidenceRehashed=False,
                            elapsedSeconds=time.monotonic() - started))
        print(json.dumps(previous, indent=2))
        return

    require(all([args.summary_sha256, args.manifest_sha256, args.review_sha256]),
            'pre-delivery requires all three frozen packet/review hashes')
    exact_head(MAIN, args.baseline)
    prior = read(ROOT / PRIOR)
    require(hashlib.sha256(git(ROOT, 'show', f'{args.baseline}:{PRIOR}')).hexdigest() == sha(ROOT / PRIOR),
            'inherited certified integration differs from latest-main baseline')
    require(len(prior['sourcePremises']) == 2170, 'inherited certified source premise count')
    for relative, digest in prior['sourcePremises'].items():
        check(MAIN / relative, digest)

    summary_path = args.summary.resolve()
    summary_path.relative_to(EVIDENCE)
    check(summary_path, args.summary_sha256)
    summary = read(summary_path)
    require(summary['cell'] == CELL and summary['cellComplete'] is False and
            summary['deliveryPending'] is True, 'finite cell/pending delivery scope')
    require(set(summary['laneSet']) == LANES, 'all four exact lanes required')
    groups = set(summary['groups'])
    require(groups == GROUPS and len(groups) == len(summary['groups']), 'all eleven finite implicit groups required')
    fresh = summary['freshProduction']
    require(len(fresh) == 61 and summary['sourceBodies'] == 5 and summary['upperBodies'] == 56 and
            summary['rebuiltLowerBodies'] == 0, 'actual source5/upper56 and no lower rebuild')
    require(len({Path(name).name for name in fresh}) == 61, 'selected source basenames must be unique')
    require(SOURCE_NAMES <= {Path(name).name for name in fresh} and
            DRAFT_NAMES <= {Path(name).name for name in fresh}, 'current implicit and Draft publisher bodies')
    for name, digest in fresh.items():
        Path(name).relative_to(ROOT / 'Sources')
        check(name, digest)
    for key in ['fixture', 'runner']:
        entry(summary[key])
    manifest_path = entry(summary['manifest'])
    require(summary['manifest']['sha256'] == args.manifest_sha256, 'frozen manifest binding')
    manifest = read(manifest_path)
    require(manifest['cell'] == CELL, 'manifest cell')
    archived, durable = {}, {}
    for original, item in manifest['files'].items():
        path = entry(item)
        resolved = path.resolve()
        relative = resolved.relative_to(ROOT / 'Tests')
        require('Evidence' in relative.parts, 'manifest payload must remain in a tracked Tests evidence directory')
        if not resolved.is_relative_to(EVIDENCE):
            # Existing immutable evidence is reused in place, never copied or
            # retrospectively represented as a current-cell compilation.
            check(MAIN / resolved.relative_to(ROOT), item['sha256'])
        authority = item.get('originalPath', original)
        if authority != original:
            require(original == authority + '#' + item['sha256'], 'exact historical path/digest manifest key')
        key = (authority, item['sha256'])
        require(key not in archived or archived[key] == path, 'ambiguous original path/digest archive')
        archived[key] = path
        durable[str(path.relative_to(ROOT))] = item['sha256']
    require(len(manifest['files']) == manifest['fileEntries'], 'manifest entry count')
    cas_paths = set(archived.values())
    require(len(cas_paths) == manifest['casFiles'] and
            sum(path.stat().st_size for path in cas_paths) == manifest['casBytes'], 'CAS count/bytes')
    review_path = EVIDENCE / 'REVIEW.md'
    check(review_path, args.review_sha256)
    review = review_path.read_text()
    require(CELL in review and 'Verdict: PASS' in review.splitlines() and
            args.summary_sha256 in review and args.manifest_sha256 in review,
            'comprehensive PASS must bind this exact frozen packet')
    for path in [summary_path, manifest_path, review_path, EVIDENCE / 'acceptance/VERIFICATION.md', Path(__file__).resolve()]:
        durable[str(path.relative_to(ROOT))] = sha(path)

    def saved(name, expected):
        path = archived.get((name, expected), Path(name))
        check(path, expected)
        return path

    def successful(run, lane):
        require(run['exitCode'] == 0 and run['boundedStop'] is None and
                not run['ownedDescendantsRemaining'] and run.get('postHashesMatch', True) is True,
                f'unsuccessful or unclean run: {run["label"]}')
        wall = run.get('wallLimitSeconds', run.get('wallSeconds'))
        cpu = run.get('cpuLimitSecondsPerProcess', run.get('perProcessCPUSeconds'))
        override = run.get('operationalGuardOverride')
        if override is None:
            require(wall == 120 and cpu == 120 and run['ownedCPUSeconds'] == 120,
                    'default compiler/fixture/runtime 120-second process bounds')
        else:
            stage = run['label'].removeprefix('regression-')
            persistent = stage in {'fixture-object', 'fixture-module'}
            expected = dict(wall=360, perProcessCPU=360, ownedCPU=360) if stage == 'fixture-object' else (
                dict(wall=180, perProcessCPU=180, ownedCPU=180) if stage == 'fixture-module' else
                dict(wall=240, perProcessCPU=360, ownedCPU=360))
            require(lane == 'embedded' and stage in
                    {'upper-module-compile', 'upper-compile', 'regression-compile', 'fixture-object', 'fixture-module'} and
                    wall == expected['wall'] and cpu == expected['perProcessCPU'] and
                    run['ownedCPUSeconds'] == expected['ownedCPU'] and override['limits'] == expected and
                    override['scope'] and override['reason'],
                    'only the observed Embedded compiler classes may use their exact declared operational guards')
            module_stage = stage == 'upper-module-compile'
            require(len(override['priorStops']) == (2 if module_stage else 1),
                    'exact concrete prior compiler stops required')
            labels = set()
            for stop in override['priorStops']:
                original = str(stop['path'])
                require('-embedded-' in original, 'operational exception must refer to Embedded stops')
                prior_stop = read(saved(original, stop['sha256']))
                if persistent:
                    require(stop['sha256'] == 'e603bdc046b70a4f452d645333a0fb92b9a11c037619c9f790400a4d53f988a0' and
                            prior_stop['boundedStop'] == 'wall-limit' and prior_stop['exitCode'] != 0 and
                            prior_stop['wallSeconds'] == 240 and prior_stop['perProcessCPUSeconds'] == 360 and
                            prior_stop['ownedCPUSeconds'] == 360,
                            'persistent jobs must retain the actual unsuccessful compound-driver wall stop')
                else:
                    require(prior_stop['boundedStop'] == 'owned-cpu-limit' and prior_stop['exitCode'] != 0 and
                            prior_stop['wallSeconds'] == 120 and prior_stop['perProcessCPUSeconds'] == 120 and
                            prior_stop['ownedCPUSeconds'] == 120,
                            'operational exception basis must retain original unsuccessful 120-second guards')
                    if not module_stage:
                        require(stop['sha256'] == '93dad18f4f5f3d92662b158142d751fdbadc401684652bc25e2edf99080cfc04',
                                'imported-module fixture compiler policy must bind the actual v6 stop')
                labels.add(prior_stop['label'])
            require(labels == ({'upper-compile', 'upper-module-compile'} if module_stage else {'upper-compile'}),
                    'exact rejected compiler-stage basis')
            if not module_stage and not persistent:
                require(any(Path(value).name == 'libImplicitAcceptanceUpper.a' for value in run['command']) and
                        not any(Path(value).name in {Path(name).name for name in fresh} for value in run['command']),
                        'expanded fixture guard only applies to a compiler importing the accepted immutable upper module')
            samples = override['sampledCPUByPID']
            require(samples and abs(sum(samples.values()) - run['sampledOwnedCPUSeconds']) < 0.000001,
                    'actual owned CPU samples must match the recorded aggregate')

    def original_receipt(item):
        matches = {name for name, digest in archived if digest == item['sha256'] and name.endswith('.json')}
        declared = locate(item.get('originalPath', item['path']))
        if str(declared) in matches:
            saved(str(declared), item['sha256'])
            return declared
        if not matches and declared.parent.name != 'cas' and declared.is_relative_to(ROOT / 'Tests'):
            relative = declared.relative_to(ROOT)
            require('Evidence' in relative.parts and declared.suffix == '.json' and
                    git(ROOT, 'ls-files', '--', str(relative)).decode().splitlines() == [str(relative)],
                    'direct packet-declared original receipt must already be Git-tracked evidence')
            check(declared, item['sha256'])
            durable[str(relative)] = item['sha256']
            return declared
        require(len(matches) == 1, f'unique original receipt path: {item["path"]}')
        return Path(next(iter(matches)))

    def bind_historical_inputs(checks):
        for authority in ['fixture', 'runner']:
            name = summary[authority]['path']
            digest = checks.get(name)
            if digest is not None and digest != summary[authority]['sha256']:
                copies = [candidate for candidate, value in checks.items()
                          if candidate != name and value == digest and
                          Path(candidate).suffix == Path(name).suffix and (candidate, digest) in archived]
                require(copies or (name, digest) in archived,
                        f'exact pre/post-admitted copied historical {authority} binding')
                if copies:
                    archived[(name, digest)] = archived[(copies[0], digest)]

    def inspect(item, accepted=False, lane=None):
        record = read(entry(item))
        bind_historical_inputs(record.get('checks', {}))
        for field in ['checks', 'freshProduction', 'products', 'inputProducts']:
            for name, digest in record.get(field, {}).items():
                saved(name, digest)
        runs = record.get('runs', [record] if 'label' in record else [])
        require(runs, 'receipt has no actual runs')
        labels = {}
        for run in runs:
            label = run['label']
            require(label not in labels, 'duplicate run labels')
            labels[label] = run
            if 'rawReceipt' in run:
                raw_item = run['rawReceipt']
                raw = read(entry(raw_item))
                require({key: value for key, value in run.items() if key not in {'rawReceipt', 'logPath'}} == raw,
                        'composed run must equal the original per-stage receipt')
                require(Path(run['logPath']) == original_receipt(raw_item).parent / (label + '.log'),
                        'actual per-stage log location')
            elif accepted and 'runs' in record:
                require(False, 'composed acceptance requires exact per-stage raw receipt binding')
            bind_historical_inputs(run.get('checks', {}))
            for field in ['checks', 'products', 'inputProducts']:
                for name, digest in run.get(field, {}).items():
                    saved(name, digest)
            log = str(original_receipt(item).parent / (label + '.log'))
            # Composed receipts explicitly retain per-stage original log paths.
            if 'logPath' in run:
                log = run['logPath']
            saved(log, run['logSHA256'])
            if accepted:
                successful(run, lane)
        return record, labels

    def assembly(part, record, runs, lane, regression=False):
        original = read(entry(part['assemblyCommand']))
        if 'persistentAssemblyReceipt' not in part:
            compilers = [run for run in runs.values() if run['command'] == original]
            require(len(compilers) == 1, 'actual successful compiler command required')
            return original, compilers[0]
        require(lane == 'embedded' and 'upperModuleReceipt' in part,
                'persistent fixture jobs require the admitted Embedded upper module')
        aggregate = read(entry(part['persistentAssemblyReceipt']))
        plan = read(entry(part['persistentJobPlan']))
        expected_label = 'regression-persistent-assembly' if regression else 'upper-persistent-assembly'
        require(aggregate['label'] == expected_label and aggregate['assemblyKind'] == 'four-exact-driver-jobs' and
                plan['originalCommand'] == original and plan['onlyOutputAndCorrespondingInputPathsChanged'] is True,
                'derived persistent assembly must bind the original actual driver command')
        printed, executed, mapping = plan['printedJobs'], plan['executedCommands'], plan['outputMapping']
        printed_text = entry(part['persistentPrintedJobs']).read_text()
        require([shlex.split(line) for line in printed_text.splitlines() if line.strip()] == printed,
                'persistent plan must equal the actual driver-print-jobs output')
        require(len(printed) == len(executed) == len(part['persistentJobReceipts']) == 4 and
                aggregate['jobReceipts'] == [dict(path=str(original_receipt(item)), sha256=item['sha256'])
                                             for item in part['persistentJobReceipts']],
                'exact four original immutable job receipts through durable CAS references')
        require('-c' in printed[0] and '-emit-module' in printed[1] and '-modulewrap' in printed[2] and
                Path(printed[3][0]).name == 'clang', 'actual object/module/modulewrap/link driver phases')
        output_flags = {'-o', '-emit-module-doc-path', '-emit-module-source-info-path'}
        printed_outputs = {command[i + 1] for command in printed for i in range(len(command) - 1)
                           if command[i] in output_flags}
        require(set(mapping) == printed_outputs and len(set(mapping.values())) == len(mapping) and
                all(Path(value).is_relative_to(ROOT / '.build') for value in mapping.values()),
                'only exact driver output paths may be persisted')
        require([[mapping.get(value, value) for value in command] for command in printed] == executed,
                'executed jobs may change output and corresponding input paths only')
        require(printed[3][printed[3].index('-o') + 1] == original[original.index('-o') + 1],
                'actual driver final output must equal the printed linker output')
        accumulated, base_checks = {}, None
        labels = [('regression-' if regression else '') + label for label in
                  ['fixture-object', 'fixture-module', 'fixture-modulewrap', 'fixture-link']]
        for index, item in enumerate(part['persistentJobReceipts']):
            job, job_runs = inspect(item, accepted=True, lane=lane)
            require(len(job_runs) == 1, 'one actual bounded persistent compiler job')
            run = next(iter(job_runs.values()))
            require(run['label'] == labels[index] and run['command'] == executed[index] and
                    run['inputProducts'] == accumulated and run['label'] in runs,
                    'exact job argv/order and prior-product readmission')
            composed = {key: value for key, value in runs[run['label']].items()
                        if key not in {'rawReceipt', 'logPath'}}
            require(composed == run, 'accepted composed compiler job must equal its original raw receipt')
            if base_checks is None:
                base_checks = run['checks']
            require(run['checks'] == base_checks, 'persistent jobs must retain the same source/prefix/fixture admission')
            outputs = {executed[index][i + 1] for i in range(len(executed[index]) - 1)
                       if executed[index][i] in output_flags}
            require(set(run['products']) == outputs and not (outputs & accumulated.keys()),
                    'each actual job must bind exactly its own successful output products')
            for value in executed[index]:
                if value in accumulated:
                    require(run['inputProducts'][value] == accumulated[value], 'actual consumed prior compiler product')
            accumulated.update(run['products'])
        final = executed[3][executed[3].index('-o') + 1]
        require(aggregate['checks'] == base_checks and aggregate['inputProducts'] == accumulated and
                aggregate['products'] == {final: accumulated[final]} and
                record['products'].get(final) == accumulated[final],
                'derived assembly metadata must retain the exact successful job-to-executable chain')
        # This metadata proxy supplies admitted inputs to the common binding checks;
        # all success claims above come from the four original bounded job receipts.
        effective = [mapping.get(value, value) for value in original]
        return effective, dict(checks=base_checks, command=effective)

    def compiler_profile(command, lane):
        require('swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc' in command[0], 'fixed release compiler')
        require(command[command.index('-num-threads') + 1] == '2', 'actual compiler threads')
        target, sdk = command[command.index('-target') + 1], command[command.index('-sdk') + 1]
        embedded = any(command[i:i + 2] == ['-enable-experimental-feature', 'Embedded']
                       for i in range(len(command) - 1))
        require(embedded == (lane == 'embedded'), 'Embedded compiler mode')
        if lane in {'native', 'asan'}:
            require(target == 'arm64-apple-macos15.0' and sdk.endswith('/MacOSX27.0.sdk'), 'Native target/SDK')
            require(('-sanitize=address' in command) == (lane == 'asan'), 'ASAN mode')
        else:
            require(target == 'wasm32-unknown-wasip1' and '/swift-6.4.0-RELEASE_wasm.artifactbundle/' in sdk,
                    'matching release WebAssembly SDK')
            resource = command[command.index('-resource-dir') + 1]
            require(resource.endswith('/usr/lib/swift' if embedded else '/usr/lib/swift_static'),
                    'portable runtime resource directory')

    bindings = summary['compiledBindings']
    require(len(bindings) == 61 and {item['originalPath'] for item in bindings} == set(fresh),
            'all 61 actual selected compiler inputs required')
    for binding in bindings:
        original = entry(binding['original']).read_bytes()
        compiled = entry(binding['compiledInput']).read_bytes()
        require(binding['original']['sha256'] == fresh[binding['originalPath']] and compiled.endswith(original) and
                hashlib.sha256(compiled[:-len(original)]).hexdigest() == binding['prefixSHA256'],
                'exact current original body and explicit import prefix')

    cached = summary['cachedImplicitNominals']
    require(len(cached) == 9 and {Path(name).name for name in cached} == CACHED_NAMES,
            'exact nine cached implicit original nominal bodies')
    for name, digest in cached.items():
        relative = str(Path(name).relative_to(ROOT))
        require(prior['sourcePremises'].get(relative) == digest,
                'cached nominal must match unchanged latest-main source authority')
        check(name, digest)
    draft = summary['draftPublisherRegression']
    draft_groups = set(draft['groups'])
    require(draft_groups == {'ordinary', 'grouping'} and
            {Path(name).name for name in draft['bodies']} == DRAFT_NAMES and
            set(draft['bodies']) <= set(fresh), 'explicit current Draft publisher regression scope')

    def fixture_equivalence(old, evolution, selected):
        require(entry(evolution['old']) == old and
                evolution['current']['sha256'] == summary['fixture']['sha256'],
                'historical/current fixture owners')
        before, after = old.read_bytes(), entry(evolution['current']).read_bytes()
        require(set(evolution['unchangedGroups']) == GROUPS - {'limits'} and
                selected <= set(evolution['unchangedGroups']), 'only unchanged non-limits groups may compose')
        first = b'    } else if selected == "limits" {'
        following = b'    } else if selected == "budgets" {'
        require(before.count(first) == after.count(first) == 1 and
                before.count(following) == after.count(following) == 1,
                'unique actual limits branch boundaries')
        old_start, new_start = before.index(first), after.index(first)
        old_end, new_end = before.index(following, old_start), after.index(following, new_start)
        old_branch, new_branch = before[old_start:old_end], after[new_start:new_end]
        require(hashlib.sha256(old_branch).hexdigest() == evolution['oldBranchSHA256'] and
                hashlib.sha256(new_branch).hexdigest() == evolution['newBranchSHA256'],
                'exact changed limits branch hashes')
        require(before[:old_start] + before[old_end:] == after[:new_start] + after[new_end:],
                'whole executable fixture outside limits branch must remain identical')

    nominal_chains = summary['cachedImplicitNominalBindings']
    require(len(nominal_chains) == 4 and {item['lane'] for item in nominal_chains} == LANES,
            'one explicit cached original generation/product chain per lane')
    nominal_chains = {item['lane']: item for item in nominal_chains}

    def cached_chain(lane, source_run, assembly_command, upper_checks, link_command=None, link_checks=None):
        link_command = assembly_command if link_command is None else link_command
        link_checks = upper_checks if link_checks is None else link_checks
        chain = nominal_chains[lane]
        generation_path = entry(chain['generationReceipt'])
        generation = read(generation_path)
        for name, digest in cached.items():
            relative = str(Path(name).relative_to(ROOT))
            require(generation['source_sha256'].get(relative) == digest,
                    'cached module generation must bind the actual unchanged implicit source body')
        source_checks = source_run.get('checks', {})
        generation_original = str(original_receipt(chain['generationReceipt']))
        for checks in [source_checks, upper_checks]:
            if generation_original in checks:
                require(checks[generation_original] == chain['generationReceipt']['sha256'],
                        'a recorded historical generation receipt must match the exact original authority')
        module = chain['module']
        module_path = Path(module['path'])
        module_directory = module_path.parent if module_path.name == 'CADGeometry.swiftmodule' else module_path.parent.parent
        require((module_path.name == 'CADGeometry.swiftmodule' or module_path.parent.name == 'CADGeometry.swiftmodule') and
                generation['products'][module['producedPath']] == module['sha256'] and
                source_checks.get(module['path']) == module['sha256'] and
                upper_checks.get(module['path']) == module['sha256'],
                'original generated CADGeometry nominal product must equal the imported lane module')
        saved(module['path'], module['sha256'])
        for command in [source_run['command'], assembly_command]:
            imports = [command[i + 1] for i in range(len(command) - 1) if command[i] == '-I']
            require(str(module_directory) in imports, 'actual compiler module search path binding')
        comparison = read(entry(chain['currentComparison']))
        compared = comparison.get('sources', comparison.get('sourcePremises', comparison.get('checks', {})))
        require(all(compared.get(name) == digest for name, digest in cached.items()),
                'explicit current unchanged-source comparison receipt')
        require(chain['archiveBindings'], 'actual linked cached geometry archive chain required')
        for archive in chain['archiveBindings']:
            producer_path = entry(archive['generationReceipt'])
            producer = read(producer_path)
            require(producer['success'] is True and producer['inputs'][archive['producedPath']] == archive['sha256'] and
                    archive['path'] in link_command and link_checks.get(archive['path']) == archive['sha256'],
                    'actual linked original geometry archive generation/product binding')
            original = str(original_receipt(archive['generationReceipt']))
            if original in link_checks:
                require(link_checks[original] == archive['generationReceipt']['sha256'],
                        'a recorded historical archive receipt must match the exact original authority')
            ar_runs = [run for run in producer['runs'] if run['label'] == 'archive-CADGeometry']
            require(len(ar_runs) == 1 and ar_runs[0]['exitCode'] == 0 and
                    ar_runs[0]['command'][2] == archive['producedPath'], 'actual successful geometry archive creation')
            ar = ar_runs[0]
            archived_runs = read(entry(archive['runs']))
            require([run for run in archived_runs if run['label'] == 'archive-CADGeometry'] == [ar],
                    'archive receipt must equal its original saved command run')
            before = read(entry(archive['inputsBefore']))
            objects = archive['objects']
            require(objects and len({item['path'] for item in objects}) == len(objects), 'explicit unique source object bindings')
            names = {Path(item['path']).name for item in objects}
            require((len(objects) == 1 and names == {'CADGeometry.o'}) or
                    names == {name + '.o' for name in CACHED_NAMES},
                    'actual whole-module object or exact nine original implicit object inputs')
            for obj in objects:
                require(obj['path'] in ar['command'][3:] and
                        producer['inputs'][obj['path']] == before[obj['path']] ==
                        generation['products'][obj['producedPath']] == obj['sha256'],
                        'original source/module generation products must be actual archive inputs')
            log = str(original_receipt(archive['generationReceipt']).parent / 'archive-CADGeometry.log')
            saved(log, producer['logs']['archive-CADGeometry.log'])
            saved(archive['path'], archive['sha256'])

    covered = {lane: set() for lane in LANES}
    for part in summary['accepted']:
        lane, selected = part['lane'], set(part['groups'])
        require(lane in LANES and selected and selected <= groups and not (selected & covered[lane]),
                'unknown lane/group or duplicate accepted scope')
        record, runs = inspect(part['receipt'], accepted=True, lane=lane)
        require(record['cell'] == CELL and record['lane'] == lane and record['success'] is True and
                record['postHashesMatch'] is True and record['freshProduction'] == fresh and
                record['rebuiltLowerBodies'] == 0 and part['rawSuccess'] is True and
                part['rawState'] == record['state'] and part['preAndPostAdmissionPassed'] is True,
                'accepted raw status/current61 scope')
        require(part['runs'] == record['runs'] and part['products'] == record['products'], 'raw runs/products binding')
        wanted = {'runtime-' + group for group in selected}
        require(set(part['successRunLabels']) == wanted and wanted <= runs.keys(), 'selected runtime success labels')
        module, module_runs = inspect(part['sourceModuleReceipt'], accepted=True, lane=lane)
        require(len(module_runs) == 1, 'one actual source compiler run')
        source_run = next(iter(module_runs.values()))
        source_command = source_run['command']
        assembly_command, fixture_compiler = assembly(part, record, runs, lane)
        compiler_profile(source_command, lane)
        compiler_profile(assembly_command, lane)
        compiler, body_command = fixture_compiler, assembly_command
        if 'upperModuleReceipt' in part:
            require(lane == 'embedded', 'split upper module belongs only to the observed Embedded CPU stop')
            upper_module, upper_runs = inspect(part['upperModuleReceipt'], accepted=True, lane=lane)
            body_command = read(entry(part['upperModuleCommand']))
            compiler_profile(body_command, lane)
            matching = [run for run in upper_runs.values() if run['command'] == body_command]
            require(len(matching) == 1, 'actual successful split upper compiler command')
            compiler = matching[0]
            upper_products = upper_module.get('products', compiler.get('products', {}))
            upper_archives = [name for name in upper_products if name.endswith('.a')]
            upper_modules = [name for name in upper_products if name.endswith('.swiftmodule')]
            final_checks = fixture_compiler.get('checks', record['checks'])
            require(len(upper_archives) == len(upper_modules) == 1 and upper_archives[0] in assembly_command and
                    all(final_checks.get(name) == upper_products[name] for name in upper_archives + upper_modules),
                    'final fixture compiler must admit and link the exact fresh upper module/archive')
            imports = [assembly_command[i + 1] for i in range(len(assembly_command) - 1) if assembly_command[i] == '-I']
            require(str(Path(upper_modules[0]).parent) in imports, 'final fixture must select actual fresh upper nominal module')
            require({Path(name).name for name in assembly_command if name.endswith('.swift')} == {'Proof.swift'},
                    'split fixture compiler must compile only the original fixture prefix/body')
        cached_chain(lane, source_run, body_command, compiler.get('checks', record['checks']),
                     assembly_command, fixture_compiler.get('checks', record['checks']))
        source_inputs = [name for name in source_command if name.endswith('.swift')]
        upper_inputs = [name for name in body_command if name.endswith('.swift') and Path(name).name in
                        ({Path(path).name for path in fresh} - SOURCE_NAMES)]
        require(len(source_inputs) == 5 and {Path(name).name for name in source_inputs} == SOURCE_NAMES,
                'actual five source compiler inputs')
        require(len(upper_inputs) == 56 and {Path(name).name for name in upper_inputs} ==
                {Path(name).name for name in fresh} - SOURCE_NAMES, 'actual 56 upper compiler inputs')
        expected_extra = {'ActualSelectorDeclineAdapters.swift'}
        if 'upperModuleReceipt' not in part:
            expected_extra.add('Proof.swift')
        require({Path(name).name for name in body_command if name.endswith('.swift')} -
                {Path(name).name for name in upper_inputs} == expected_extra,
                'exact selected upper namespace and actual diagnostic selector adapter/fixture')
        for name in source_inputs + upper_inputs:
            checks = source_run.get('checks', module.get('checks', {})) if name in source_inputs else compiler.get('checks', record['checks'])
            current = [path for path in fresh if Path(path).name == Path(name).name]
            require(len(current) == 1 and saved(name, checks[name]).read_bytes().endswith(Path(current[0]).read_bytes()),
                    'actual compiled input must retain current original bytes')
        products = module.get('products', source_run.get('products', {}))
        archives = [name for name in products if name.endswith('.a')]
        require(len(archives) == 1 and archives[0] in assembly_command and
                record['checks'].get(archives[0], fixture_compiler.get('checks', {}).get(archives[0])) == products[archives[0]],
                'admitted source product actually linked and hashed at upper compile')
        executable = assembly_command[assembly_command.index('-o') + 1]
        require(executable in record['products'], 'compiler output must be runtime product')
        for label in wanted:
            run = runs[label]
            require(executable in run['command'] and run['command'][-1] == label.removeprefix('runtime-'),
                    'actual runtime executable/group')
            runtime_products = run.get('inputProducts', {})
            require(runtime_products.get(executable) == record['products'][executable],
                    'runtime pre/post executable binding')
        fixture = entry(part['compiledFixture'])
        proof_inputs = [name for name in assembly_command if Path(name).name == 'Proof.swift']
        checks = fixture_compiler.get('checks', record['checks'])
        require(len(proof_inputs) == 1 and saved(proof_inputs[0], checks[proof_inputs[0]]).read_bytes().endswith(fixture.read_bytes()),
                'actual Proof input/exact compiled fixture')
        if sha(fixture) != summary['fixture']['sha256']:
            fixture_equivalence(fixture, summary['fixtureEvolution'], selected)
        covered[lane].update(selected)
    require(all(value == groups for value in covered.values()), 'four-lane complete group coverage')
    draft_covered = {lane: set() for lane in LANES}
    draft_fixture = entry(draft['fixture'])
    require(draft_fixture == ROOT / 'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift',
            'actual existing Draft regression fixture')
    adapted_fixture = draft_fixture.read_text().replace(
        'DraftZeroRuledPort.CurveSurfaceIntersectionResult', 'CurveSurfaceIntersectionResult').replace(
        'DraftZeroRuledPort.DefaultCurveSurfaceIntersector', 'DefaultCurveSurfaceIntersector').encode()
    for part in draft['accepted']:
        lane, selected = part['lane'], set(part['groups'])
        require(lane in LANES and selected and selected <= draft_groups and
                not (selected & draft_covered[lane]), 'Draft regression accepted lane/group scope')
        record, runs = inspect(part['receipt'], accepted=True, lane=lane)
        require(record['cell'] == CELL and record['lane'] == lane and record['success'] is True and
                record['freshProduction'] == fresh and record['postHashesMatch'] is True and
                record['rebuiltLowerBodies'] == 0 and part['rawSuccess'] is True and
                part['rawState'] == record['state'] and part['preAndPostAdmissionPassed'] is True and
                part['runs'] == record['runs'] and part['products'] == record['products'],
                'actual final current Draft regression receipt scope')
        wanted = {'regression-' + group for group in selected}
        require(set(part['successRunLabels']) == wanted and wanted <= runs.keys(), 'Draft actual successful groups')
        command, compiler = assembly(part, record, runs, lane, regression=True)
        compiler_profile(command, lane)
        checks = compiler.get('checks', record['checks'])
        body_command, body_checks = command, checks
        if 'upperModuleReceipt' in part:
            require(lane == 'embedded', 'only Embedded uses the observed module split')
            upper_module, upper_runs = inspect(part['upperModuleReceipt'], accepted=True, lane=lane)
            body_command = read(entry(part['upperModuleCommand']))
            compiler_profile(body_command, lane)
            matching = [run for run in upper_runs.values() if run['command'] == body_command]
            require(len(matching) == 1, 'Draft actual reused current upper module compiler')
            body_checks = matching[0].get('checks', upper_module.get('checks', {}))
            upper_products = upper_module.get('products', matching[0].get('products', {}))
            archives = [name for name in upper_products if name.endswith('.a')]
            modules = [name for name in upper_products if name.endswith('.swiftmodule')]
            require(len(archives) == len(modules) == 1 and archives[0] in command and
                    all(checks.get(name) == upper_products[name] for name in archives + modules),
                    'Draft fixture must link the actual fresh upper module/archive')
            imports = [command[i + 1] for i in range(len(command) - 1) if command[i] == '-I']
            require(str(Path(modules[0]).parent) in imports, 'Draft actual fresh upper module search path')
        upper_inputs = [name for name in body_command if name.endswith('.swift') and Path(name).name in
                        ({Path(path).name for path in fresh} - SOURCE_NAMES)]
        require(len(upper_inputs) == 56 and {Path(name).name for name in upper_inputs} ==
                {Path(name).name for name in fresh} - SOURCE_NAMES, 'Draft uses actual current upper56')
        for name in upper_inputs:
            originals = [path for path in fresh if Path(path).name == Path(name).name]
            require(len(originals) == 1 and saved(name, body_checks[name]).read_bytes().endswith(Path(originals[0]).read_bytes()),
                    'current Draft/shared publisher original body must be actually compiled')
        module, source_runs = inspect(part['sourceModuleReceipt'], accepted=True, lane=lane)
        require(len(source_runs) == 1, 'Draft actual source module compiler receipt')
        source_run = next(iter(source_runs.values()))
        cached_chain(lane, source_run, body_command, body_checks, command, checks)
        compiler_profile(source_run['command'], lane)
        source_inputs = [name for name in source_run['command'] if name.endswith('.swift')]
        require(len(source_inputs) == 5 and {Path(name).name for name in source_inputs} == SOURCE_NAMES,
                'Draft linked module is the current implicit source5')
        for name in source_inputs:
            original = next(path for path in fresh if Path(path).name == Path(name).name)
            require(saved(name, source_run.get('checks', module.get('checks', {}))[name]).read_bytes().endswith(Path(original).read_bytes()),
                    'Draft linked module source body must match current original')
        products = module.get('products', source_run.get('products', {}))
        archives = [name for name in products if name.endswith('.a')]
        require(len(archives) == 1 and archives[0] in command and checks.get(archives[0]) == products[archives[0]],
                'Draft actual admitted source archive link')
        proofs = [name for name in command if Path(name).name == 'RegressionProof.swift']
        require(len(proofs) == 1 and saved(proofs[0], checks[proofs[0]]).read_bytes().endswith(adapted_fixture),
                'Draft original fixture only has the two explicit nominal qualifications removed')
        shape_inputs = [name for name in command if Path(name).name == 'RegressionShape.swift']
        require(len(shape_inputs) == 1, 'actual extracted Draft constructor helpers required')
        atlas = ROOT / 'Tests/OriginalPolylineAtlasLiftVerification/Proof.swift'
        polyline = ROOT / 'Tests/OriginalPolylineSurfaceLiftVerification/Proof.swift'
        saved(str(atlas), checks[str(atlas)])
        saved(str(polyline), checks[str(polyline)])
        shape = atlas.read_text().split('    nonisolated static func shape(', 1)[1].split('    nonisolated static func prepared', 1)[0]
        points = polyline.read_text().split('    nonisolated static func points(', 1)[1].split('    nonisolated static func shape', 1)[0]
        expected_helper = ('import CADCore\n@testable import CADGeometry\nstruct PolylineAtlasLiftProof {\n'
            ' typealias Admission=DraftZeroRuledAcceptance.Admission\n nonisolated static func shape(' + shape +
            '}\nstruct PolylineLiftProof {\n nonisolated static func points(' + points + '}\n').encode()
        require(saved(shape_inputs[0], checks[shape_inputs[0]]).read_bytes() == expected_helper,
                'Draft constructor helpers must retain the exact existing source expressions')
        derivative = str(ROOT / 'Tests/OriginalDerivativeLiftHostVerification/Shape.swift')
        require(derivative in command, 'actual existing derivative constructor helper input required')
        saved(derivative, checks[derivative])
        executable = command[command.index('-o') + 1]
        require(executable in record['products'], 'Draft compiler output/runtime product')
        if 'runtimeResumePremises' in part:
            require(lane == 'embedded' and 'persistentAssemblyReceipt' in part,
                    'metadata-only resume belongs to the actual persistent Embedded Draft assembly')
            prepared_path = entry(part['preparedPremises'])
            prepared, derived = read(prepared_path), read(entry(part['derivedPremises']))
            stop = read(entry(part['metadataStop']))
            require(stop['kind'] == 'runner-metadata-preflight' and stop['publicCalls'] == 0 and
                    stop['compileSuccess'] is True and stop['recoveredExact'] is True and
                    stop['originalPreparedPremisesSHA256'] == part['preparedPremises']['sha256'] and
                    stop['derivedPremisesSHA256'] == part['derivedPremises']['sha256'],
                    'preflight metadata stop must remain separate from public runtime and compilation success')
            require(all(derived.get(key) == value for key, value in prepared.items() if key != 'checks') and
                    all(derived['checks'].get(key) == value for key, value in prepared['checks'].items()) and
                    set(derived) - set(prepared) == {'persistentJobPlan', 'persistentJobReceipts'},
                    'derived metadata may extend exact prepared metadata without overwriting its authority')
            prepared_original = str(original_receipt(part['preparedPremises']))
            require(checks.get(prepared_original) == part['preparedPremises']['sha256'],
                    'compiled persistent jobs must admit the exact recovered prepared metadata')
            resume = read(entry(part['runtimeResumePremises']))
            require(resume['compileAndLinkRepetitions'] == 0 and
                    resume['products'] == {executable: record['products'][executable]},
                    'metadata repair must reuse the exact successful executable without compiler replay')
            bind_historical_inputs(resume['checks'])
            for name, digest in resume['checks'].items():
                saved(name, digest)
            for key in ['preparedPremises', 'derivedPremises', 'metadataStop']:
                require(resume['checks'].get(str(original_receipt(part[key]))) == part[key]['sha256'],
                        'runtime-only resumption must admit both immutable metadata owners and its separate stop')
            for label in wanted:
                require(runs[label]['checks'].get(str(original_receipt(part['runtimeResumePremises']))) ==
                        part['runtimeResumePremises']['sha256'], 'actual resumed runtime must admit its exact resume premise')
        for label in wanted:
            run = runs[label]
            require(executable in run['command'] and run['command'][-1] == label.removeprefix('regression-') and
                    run.get('inputProducts', {}).get(executable) == record['products'][executable],
                    'Draft actual runtime group and exact compiler product')
        draft_covered[lane].update(selected)
    require(all(value == draft_groups for value in draft_covered.values()),
            'final current Draft ordinary/grouping regression missing a lane')
    for item in summary.get('retainedLowerEvidence', []):
        entry(item)
    entry(summary['originalObservation'])
    for diagnostic in summary['diagnostics']:
        require(diagnostic['rawSuccess'] is False and diagnostic['scope'], 'diagnostic must remain unsuccessful')
        record = read(entry(diagnostic['receipt']))
        if 'priorFrozenPacket' in diagnostic:
            require(diagnostic['scope'].startswith('F1:') and
                    diagnostic['priorFrozenPacket'] == summary['f1PriorPacket'] and
                    record['label'] == 'regression-persistent-assembly' and
                    record['assemblyKind'] == 'four-exact-driver-jobs' and record['exitCode'] == 0,
                    'F1 prior derived assembly is inadmissible evidence, not a relabeled runtime failure')
            prior_packet = diagnostic['priorFrozenPacket']
            old_summary = read(entry(prior_packet['summary.json']))
            old_manifest = read(entry(prior_packet['manifest.json']))
            entry(prior_packet['VERIFICATION.md'])
            require(old_summary['cell'] == old_manifest['cell'] == CELL and
                    old_summary['manifest']['sha256'] == prior_packet['manifest.json']['sha256'],
                    'exact prior frozen summary/manifest authority')
            old_parts = [part for part in old_summary['draftPublisherRegression']['accepted']
                         if part['lane'] == 'embedded']
            require(len(old_parts) == 1 and old_parts[0]['persistentAssemblyReceipt']['sha256'] ==
                    diagnostic['receipt']['sha256'], 'F1 diagnostic must identify the actual prior Embedded Draft assembly')
            old_part = old_parts[0]
            old_plan = read(entry(old_part['persistentJobPlan']))
            old_object = read(entry(old_part['persistentJobReceipts'][0]))
            object_command = old_plan['executedCommands'][0]
            outputs = {object_command[index + 1] for index in range(len(object_command) - 1)
                       if object_command[index] == '-o'}
            require(old_object['label'] == 'regression-fixture-object' and old_object['exitCode'] == 0 and
                    old_object['command'] == object_command and len(outputs) == 3 and
                    len(old_object['products']) == 1 and set(old_object['products']) < outputs and
                    any(item['sha256'] == diagnostic['receipt']['sha256']
                        for item in old_manifest['files'].values()),
                    'F1 diagnostic must preserve the concrete three-output/one-recorded-product counterexample')
            continue
        require(record.get('success', False) is False, 'historical failure relabeled as success')
        runs = record.get('runs', [record] if 'label' in record else [])
        require(runs, 'historical diagnostic actual runs missing')
        if 'rawState' in diagnostic:
            require(record.get('state') == diagnostic['rawState'], 'historical diagnostic state changed')
        for run in runs:
            if 'rawReceipt' in run:
                raw = read(entry(run['rawReceipt']))
                require({key: value for key, value in run.items() if key not in {'rawReceipt', 'logPath'}} == raw,
                        'historical diagnostic run differs from raw receipt')
            log = run.get('logPath', str(original_receipt(diagnostic['receipt']).parent / (run['label'] + '.log')))
            saved(log, run['logSHA256'])

    sources = dict(prior['sourcePremises'])
    updates = {}
    for name, digest in fresh.items():
        relative = str(Path(name).relative_to(ROOT))
        if sources.get(relative) != digest:
            updates[relative] = dict(before=sources.get(relative), after=digest)
        sources[relative] = digest
    changed, deleted = {}, []
    for value in git(ROOT, 'diff', '--name-only', '-z', args.baseline, args.implementation).split(b'\0'):
        if value:
            relative = value.decode()
            if (ROOT / relative).is_file():
                changed[relative] = sha(ROOT / relative)
            else:
                deleted.append(relative)
    files = dict(sources)
    for mapping in [changed, durable]:
        for relative, digest in mapping.items():
            require(relative not in files or files[relative] == digest, f'conflicting premise: {relative}')
            files[relative] = digest
    for relative, digest in files.items():
        for directory in [ROOT, INDEPENDENT]:
            check(directory / relative, digest)
    for relative in deleted:
        require(all(not (directory / relative).exists() for directory in [ROOT, INDEPENDENT]),
                f'deletion mismatch: {relative}')
    tracked = {value.decode() for value in git(ROOT, 'ls-files', '-z', '--', *durable).split(b'\0') if value}
    require(tracked == durable.keys(), 'all durable evidence must be committed')
    protected = prior['protectedDrafts']
    protected_metadata(protected)
    for name, directory in [('source', '/private/tmp/cad-di-m4-source-support-20261009'),
                            ('consumer', '/private/tmp/cad-di-m6-consumers-20261009')]:
        for relative, digest in protected[name]['files'].items():
            check(Path(directory) / relative, digest)
    for directory in [ROOT, INDEPENDENT]:
        exact_head(directory)
    exact_head(MAIN, args.baseline)
    result = dict(cell=CELL, implementationCommit=args.implementation, mainBefore=args.baseline,
                  mainHead=args.baseline, delivered=False, implementationTree=implementation_tree, independentCheckout=str(INDEPENDENT),
                  inheritedIntegration=str(PRIOR), inheritedIntegrationSHA256=sha(ROOT / PRIOR),
                  sourcePremises=sources, premiseUpdates=updates, changedInputs=changed, deletedInputs=deleted,
                  acceptedScopedReceipts=summary['accepted'], diagnostics=summary['diagnostics'],
                  compilerBindings=bindings, compilerSelectedBodies=61, sourceBodies=5, upperBodies=56,
                  rebuiltLowerBodies=0, durableEvidence=durable, manifestOriginalReferences=len(manifest['files']),
                  deduplicatedCASFiles=len(cas_paths), protectedDrafts=protected,
                  auditReferences=references, uniqueArtifacts=len(cache), elapsedSeconds=time.monotonic() - started,
                  auditScriptSHA256=sha(__file__), buildOrRuntimeRepeated=False, gitMutated=False)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    audit()
