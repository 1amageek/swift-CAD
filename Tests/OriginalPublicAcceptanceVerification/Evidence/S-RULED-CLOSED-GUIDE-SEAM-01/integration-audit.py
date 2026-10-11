#!/usr/bin/env python3
"""Compare admitted guide evidence independently, then fast-forward main.

Usage: python3 integration-audit.py IMPLEMENTATION_COMMIT [--summary PATH]

The frozen summary supplies cell, cellComplete, groups, upperSources (27),
sourcePremises (13), lanes, diagnostics, and manifest {path, sha256}. Each lane
supplies receiptParts [{path, sha256, groups, success, successRunLabels}],
compiledUpper, compiledExistingRuledBodies (portable lanes), and compilerReceipts
[{path, sha256, kind: upper|ruled, runLabel?}]. Paths are evidence-relative unless absolute.
Optional logPaths maps run labels to evidence-relative or absolute log paths.
Receipt metadata may supply historicalComparators for exact old fixture bytes.
Diagnostics supply path, sha256, scope, admissionScope: preservedDiagnosticOnly;
only manifest-preserved bytes are checked, without readmitting historical inputs.
The manifest accepts {files: {relative: sha256|{sha256, ...}}} or a plain map.
Historical comparators are used only for their exact recorded path/hash pair.
No build, execution of a fixture, or regeneration of evidence occurs here.
"""

import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path


ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
INTEGRATION = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
MAIN = Path('/Users/1amageek/Desktop/3D/swift-CAD')
BASELINE = '287db282e2e505066228a96db603772fe0cf1d24'
RELATIVE = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/S-RULED-CLOSED-GUIDE-SEAM-01')
PRIOR = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-COLLAPSED-CLOSED-01/integration.json')
EVIDENCE = ROOT / RELATIVE
LANES = {'native', 'asan', 'wasm', 'embedded'}
GROUPS = {'oracle', 'graphs', 'empty', 'work', 'storage', 'cancel',
          'cancel-final', 'lifetime', 'identity', 'coons'}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def git(path, *args):
    return subprocess.check_output(['git', *args], cwd=path, timeout=30)


def read(path):
    return json.loads(Path(path).read_text())


def exact_head(path, head):
    require(git(path, 'rev-parse', 'HEAD').decode().strip() == head, f'HEAD: {path}')
    require(not git(path, 'status', '--porcelain=v1', '-z'), f'dirty checkout: {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('implementation')
    parser.add_argument('--summary', type=Path, default=EVIDENCE / 'summary.json')
    args = parser.parse_args()
    started = time.monotonic()
    cache = {}
    references = 0

    def digest(path):
        path = Path(path)
        before = path.stat()
        key = (str(path), before.st_size, before.st_mtime_ns, before.st_ino)
        if key in cache:
            return cache[key]
        require(time.monotonic() - started < 180, 'audit wall bound exceeded')
        h = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(block)
        after = path.stat()
        require((before.st_size, before.st_mtime_ns, before.st_ino) ==
                (after.st_size, after.st_mtime_ns, after.st_ino), f'changed while hashing: {path}')
        cache[key] = h.hexdigest()
        return cache[key]

    def check(path, expected):
        nonlocal references
        require(digest(path) == expected, f'SHA256 mismatch: {path}')
        references += 1

    def locate(name):
        path = Path(name)
        return path if path.is_absolute() else EVIDENCE / path

    def protected_check(snapshot):
        for name, directory in [('source', '/private/tmp/cad-di-m4-source-support-20261009'),
                                ('consumer', '/private/tmp/cad-di-m6-consumers-20261009')]:
            path = Path(directory)
            record = snapshot[name]
            require(git(path, 'rev-parse', 'HEAD').decode().strip() == record['head'],
                    f'protected HEAD: {name}')
            index = Path(git(path, 'rev-parse', '--git-path', 'index').decode().strip())
            check(index if index.is_absolute() else path / index, record['indexSHA256'])
            status = hashlib.sha256(git(path, 'status', '--porcelain=v1', '-z')).hexdigest()
            require(status == record['statusSHA256'], f'protected status: {name}')
            for relative, sha in record['files'].items():
                check(path / relative, sha)
        check('/Users/1amageek/.codex/worktrees/source-consumer-handoff-recovery/pending-public-publisher.patch',
              snapshot['patchSHA256'])

    implementation = args.implementation
    require(git(ROOT, 'rev-parse', implementation).decode().strip() == implementation,
            'implementation must be the full commit SHA')
    exact_head(ROOT, implementation)
    exact_head(INTEGRATION, implementation)
    exact_head(MAIN, BASELINE)
    require(git(MAIN, 'branch', '--show-current').decode().strip() == 'main', 'main branch required')
    subprocess.run(['git', 'merge-base', '--is-ancestor', BASELINE, implementation],
                   cwd=ROOT, check=True, timeout=30)
    prior = read(ROOT / PRIOR)
    require(hashlib.sha256(git(ROOT, 'show', f'{BASELINE}:{PRIOR}')).hexdigest() == digest(ROOT / PRIOR),
            'collapsed integration premise changed after baseline')
    protected = prior['protectedDrafts']
    protected_check(protected)

    summary_path = args.summary.resolve()
    summary_path.relative_to(EVIDENCE)
    summary = read(summary_path)
    require(summary['cell'] == 'S-RULED-CLOSED-GUIDE-SEAM-01', 'unexpected cell')
    require(summary['cellComplete'] is False, 'bounded regression must preserve incomplete cell status')
    require(set(summary['groups']) == GROUPS and len(summary['groups']) == 10, 'group scope mismatch')
    require(set(summary['lanes']) == LANES, 'four lane records required')
    upper = summary['upperSources']
    source = summary['sourcePremises']
    require(len(upper) == 27 and len(source) == 13 and not (upper.keys() & source.keys()),
            'expected 27 upper sources and 13 distinct source/DI premises')
    current = {**source, **upper}
    for name, sha in current.items():
        require(Path(name).is_absolute(), f'absolute current source path required: {name}')
        Path(name).relative_to(ROOT)
        check(name, sha)

    manifest_metadata = summary['manifest']
    manifest_path = locate(manifest_metadata['path'])
    manifest_path.relative_to(EVIDENCE)
    check(manifest_path, manifest_metadata['sha256'])
    manifest = read(manifest_path)
    entries = manifest.get('files', manifest)
    durable = {}
    for name, value in entries.items():
        path = EVIDENCE / name
        path.resolve().relative_to(EVIDENCE)
        sha = value['sha256'] if isinstance(value, dict) else value
        check(path, sha)
        durable[str(path.relative_to(ROOT))] = sha
    for path in [summary_path, manifest_path, EVIDENCE / 'REVIEW.md', EVIDENCE / 'VERIFICATION.md']:
        durable[str(path.relative_to(ROOT))] = digest(path)

    admitted_comparators = {}
    receipt_metadata = [item for lane in summary['lanes'].values()
                        for key in ['receiptParts', 'compilerReceipts'] for item in lane[key]]
    for metadata in receipt_metadata:
        path = locate(metadata['path'])
        check(path, metadata['sha256'])
        for name, comparator in read(path).get('historicalComparators', {}).items():
            check(comparator['path'], comparator['sha256'])
            admitted_comparators[(name, comparator['sha256'])] = comparator['path']

    def inspect_receipt(metadata, accepted=False):
        path = locate(metadata['path'])
        check(path, metadata['sha256'])
        record = read(path)
        comparator_sets = [metadata.get('historicalComparators', {}),
                           record.get('historicalComparators', {})]
        for field in ['checks', 'products', 'freshProduction']:
            for name, sha in record.get(field, {}).items():
                historical = next((mapping[name] for mapping in comparator_sets
                                   if name in mapping and mapping[name]['sha256'] == sha), None)
                if historical is not None:
                    check(locate(historical['path']), sha)
                elif (name, sha) in admitted_comparators:
                    check(admitted_comparators[(name, sha)], sha)
                else:
                    check(name, sha)
        labels = {}
        for run in record.get('runs', []):
            label = run['label']
            require(label not in labels, f'duplicate run: {path}: {label}')
            labels[label] = run
            log = metadata.get('logPaths', {}).get(label)
            check(locate(log) if log is not None else path.parent / f'{label}.log', run['logSHA256'])
            command_path = path.parent / f'{label}.json'
            if label.startswith('compile-') and (accepted or 'kind' in metadata):
                require(command_path.is_file(), f'compiler command JSON required: {command_path}')
            if command_path.is_file():
                require(read(command_path) == run['command'], f'command mismatch: {command_path}')
            require(not run.get('ownedDescendantsRemaining', []), f'owned process remains: {path}: {label}')
        if accepted:
            require(record['success'] is metadata['success'], f'raw success status changed: {path}')
            require(record['cellComplete'] is False and record['postRunAdmission'] is True,
                    f'receipt admission/status: {path}')
            expected = {f'runtime-{group}' for group in metadata['groups']}
            require(set(metadata['successRunLabels']) == expected, f'accepted run/group mismatch: {path}')
            for label in ['compile-proof', *metadata['successRunLabels']]:
                require(label in labels and labels[label]['exitCode'] == 0 and
                        labels[label]['timedOut'] is False, f'accepted run did not succeed: {path}: {label}')
            failed = [run for run in labels.values() if run['exitCode'] != 0 or run['timedOut']]
            require(bool(failed) is (metadata['success'] is False), f'raw failure was not preserved: {path}')
            if metadata['success'] is False:
                require(metadata.get('preserveFailure') is True, f'failure preservation required: {path}')
            require(record['freshProduction'] == current, f'current source snapshot differs: {path}')
        return record, labels

    accepted = {}
    compiler_records = {}
    for lane, metadata in summary['lanes'].items():
        covered = set()
        parts = []
        for part in metadata['receiptParts']:
            require(not covered.intersection(part['groups']), f'duplicate accepted groups: {lane}')
            inspect_receipt(part, accepted=True)
            covered.update(part['groups'])
            parts.append(part)
        require(covered == GROUPS, f'missing accepted groups: {lane}')
        require(metadata['compiledUpper'] == ('reused-v6-admitted27' if lane == 'native' else 'fresh27'),
                f'upper compilation scope: {lane}')
        if lane != 'native':
            require(metadata['compiledExistingRuledBodies'] == 2, f'ruled compilation scope: {lane}')
        kinds = set()
        for compiler in metadata['compilerReceipts']:
            record, labels = inspect_receipt(compiler)
            kind = compiler['kind']
            require(kind in {'upper', 'ruled'} and kind not in kinds, f'compiler kind: {lane}')
            kinds.add(kind)
            for run in labels.values():
                require(run['exitCode'] == 0 and run['timedOut'] is False, f'compiler failed: {lane}: {kind}')
            if kind == 'upper':
                # The legacy field also records 13 admitted source/DI premises.
                require(record['freshProduction'] == current, f'upper snapshot mismatch: {lane}')
            else:
                ruled = {name: sha for name, sha in source.items()
                         if Path(name).name in {'OriginalRuledSurfaceSnapshot.swift',
                                               'OriginalRuledSurfaceSnapshotProvider.swift'}}
                require(len(ruled) == 2 and all(record.get('checks', {}).get(name) == sha for name, sha in ruled.items()),
                        f'ruled two-body source mismatch: {lane}')
            compile_label = compiler.get('runLabel', 'compile-port' if kind == 'upper' else
                                         ('compile-module' if lane == 'native' else 'compile-ruled'))
            require(compile_label in labels, f'named compiler command required: {lane}: {kind}: {compile_label}')
            selected = [name for name in labels[compile_label]['command'] if name.endswith('.swift')]
            expected_sources = upper if kind == 'upper' else ruled
            require(len(selected) == len(expected_sources) and
                    {Path(name).name for name in selected} == {Path(name).name for name in expected_sources},
                    f'compiler selected body mismatch: {lane}: {kind}')
            require(all(name in record['checks'] for name in selected),
                    f'compiled generated body not admitted separately: {lane}: {kind}')
            base_generated = ROOT / '.build/s-ruled-closed-guide-seam-native-20261012-v1/OriginalRuledSurfaceSnapshot.swift'
            base_receipt = read(base_generated.parent / 'module-receipt.json')
            check(base_generated, base_receipt['checks'][str(base_generated)])
            original_snapshot = next(Path(name) for name in source
                                     if Path(name).name == 'OriginalRuledSurfaceSnapshot.swift')
            original_body = original_snapshot.read_text()
            generated_body = base_generated.read_text()
            require(generated_body.endswith(original_body), 'initial ruled generated body must retain exact original source')
            initial_prefix = generated_body[:-len(original_body)]
            prefix = generated_body.split('/// The original ruled value', 1)[0]
            prefix += '\nimport enum RetainedHostAdapters.OriginalDomainAccess\nimport class RetainedHostAdapters.OriginalIdentityReadmission\n'
            for name in selected:
                original = next(Path(path) for path in expected_sources if Path(path).name == Path(name).name)
                if kind == 'upper':
                    assembly_prefix = prefix
                elif lane == 'native':
                    assembly_prefix = initial_prefix
                else:
                    assembly_prefix = prefix + '\n@testable import CallerAdapters\n'
                expected_body = (assembly_prefix + original.read_text()).encode()
                require(hashlib.sha256(expected_body).hexdigest() == record['checks'][name],
                        f'generated prefix plus exact original body differs: {lane}: {name}')
        require(kinds == {'upper', 'ruled'}, f'missing compiler receipts: {lane}')
        accepted[lane] = parts
        compiler_records[lane] = metadata['compilerReceipts']

    for diagnostic in summary['diagnostics']:
        require(bool(diagnostic['scope']), 'diagnostic scope required')
        require(diagnostic['admissionScope'] == 'preservedDiagnosticOnly', 'historical diagnostic cannot be a success premise')
        path = locate(diagnostic['path'])
        require(durable.get(str(path.relative_to(ROOT))) == diagnostic['sha256'],
                f'diagnostic must be preserved by the evidence manifest: {path}')
        check(path, diagnostic['sha256'])

    premises = dict(prior['sourcePremises'])
    updates = {}
    for name, sha in current.items():
        relative = str(Path(name).relative_to(ROOT))
        if premises.get(relative) != sha:
            updates[relative] = {'before': premises.get(relative), 'after': sha}
        premises[relative] = sha
    changed = {}
    deleted = []
    for value in git(ROOT, 'diff', '--name-only', '-z', BASELINE, implementation).split(b'\0'):
        if not value:
            continue
        relative = value.decode()
        if (ROOT / relative).is_file():
            changed[relative] = digest(ROOT / relative)
        else:
            deleted.append(relative)
    all_files = dict(premises)
    for mapping in [changed, durable]:
        for relative, sha in mapping.items():
            require(relative not in all_files or all_files[relative] == sha,
                    f'immutable inherited premise changed outside selected snapshot: {relative}')
            all_files[relative] = sha
    for relative, sha in all_files.items():
        check(ROOT / relative, sha)
        check(INTEGRATION / relative, sha)
    for relative in deleted:
        require(not (ROOT / relative).exists() and not (INTEGRATION / relative).exists(),
                f'deletion mismatch: {relative}')
    protected_check(protected)
    exact_head(ROOT, implementation)
    exact_head(INTEGRATION, implementation)
    exact_head(MAIN, BASELINE)
    independent_seconds = time.monotonic() - started

    # Every comparison above must pass before this sole repository mutation.
    subprocess.run(['git', 'merge', '--ff-only', '--quiet', implementation],
                   cwd=MAIN, check=True, timeout=60)
    exact_head(MAIN, implementation)
    for relative, sha in all_files.items():
        check(MAIN / relative, sha)
    for relative in deleted:
        require(not (MAIN / relative).exists(), f'main deletion mismatch: {relative}')
    protected_check(protected)
    output = ROOT / '.build/guide-seam-main-integration.json'
    report = dict(scope='S-RULED-CLOSED-GUIDE-SEAM-01: ten bounded regression groups in four lanes; raw receipt cellComplete fields are preserved without deciding task completion.',
                  rawReceiptCellComplete=False, implementationCommit=implementation, mainBefore=BASELINE,
                  mainHead=implementation, mainDeliveryMode='normal fast-forward after independent admitted comparison',
                  independentCheckout=str(INTEGRATION), inheritedIntegration=str(PRIOR),
                  inheritedIntegrationSHA256=digest(ROOT / PRIOR), sourcePremises=premises,
                  premiseUpdates=updates, changedInputs=changed, deletedInputs=deleted,
                  acceptedScopedReceipts=accepted, compilerReceipts=compiler_records,
                  diagnostics=summary['diagnostics'], prerequisiteReferences=references,
                  diagnosticAdmission='Manifest-preserved raw receipts/logs/commands/available snapshots only; historical mutable inputs are not readmitted or used as success premises.',
                  upperSelectedSources=27, admittedSourceAndDIPremises=13, portableExistingRuledBodies=2,
                  durableEvidenceFiles=len(durable), evidenceManifestSHA256=digest(manifest_path),
                  summarySHA256=digest(summary_path), reviewSHA256=digest(EVIDENCE / 'REVIEW.md'),
                  verificationSHA256=digest(EVIDENCE / 'VERIFICATION.md'), protectedDrafts=protected,
                  independentSeconds=independent_seconds, totalSeconds=time.monotonic() - started,
                  broadRebuild=False, repeatedRuntime=False, uniqueHashComparisons=len(cache))
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(mainHead=implementation, rawReceiptCellComplete=False, sourcePremises=len(premises),
                          prerequisiteReferences=references, evidenceFiles=len(durable),
                          elapsedSeconds=time.monotonic() - started, output=str(output))))


if __name__ == '__main__':
    main()
