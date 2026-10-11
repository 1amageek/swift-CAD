#!/usr/bin/env python3
"""Compare admitted draft-cell premises with an independent main composition."""
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

P = argparse.ArgumentParser()
P.add_argument('phase', choices=['independent', 'main'])
P.add_argument('implementation')
args = P.parse_args()
root = Path('/private/tmp/cad-m4-m8-completion-20261010')
main = Path('/Users/1amageek/Desktop/3D/swift-CAD')
integration = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
relative = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/CS-DRAFT-ZERO-RULED-01')
evidence = root / relative
started = time.monotonic()
cache = {}


def git(path, *command):
    return subprocess.check_output(['git', *command], cwd=path, timeout=30)


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    path = Path(path)
    before = path.stat()
    key = (str(path), before.st_size, before.st_mtime_ns, before.st_ino)
    if key in cache:
        return cache[key]
    assert time.monotonic() - started < 180, 'Integration comparison exceeded its wall bound'
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    after = path.stat()
    assert (before.st_size, before.st_mtime_ns, before.st_ino) == (after.st_size, after.st_mtime_ns, after.st_ino), str(path)
    cache[key] = h.hexdigest()
    return cache[key]


def check(path, expected):
    assert digest(path) == expected, str(path)


assert git(integration, 'rev-parse', 'HEAD').decode().strip() == args.implementation
assert not git(integration, 'status', '--porcelain=v1', '-z')
if args.phase == 'main':
    assert git(main, 'rev-parse', 'HEAD').decode().strip() == args.implementation
    assert not git(main, 'status', '--porcelain=v1', '-z')

manifest = read(evidence / 'acceptance-manifest.json')
composition = read(evidence / manifest['nativeComposition']['path'])
check(evidence / manifest['nativeComposition']['path'], manifest['nativeComposition']['sha256'])
receipts = []
for key in ('firstSeven', 'remainingSix'):
    part = composition[key]
    path = evidence / part['receipt']
    check(path, part['sha256'])
    record = read(path)
    runs = [run for run in record['runs'] if run['label'] in part['groups']]
    assert len(runs) == len(part['groups'])
    assert all(run['exitCode'] == 0 and not run['timedOut'] and not run['ownedDescendantsRemaining'] for run in runs)
    if key == 'firstSeven':
        assert record['success'] is False and record['failedOperation'] == 'depth' and record['postRunAdmission']
    else:
        assert record['success'] and set(record['groups']) == set(part['groups'])
    receipts.append((key, record, part['sha256']))
assert len(composition['successfulRuntimeRuns']) == 13
for lane in manifest['accepted']:
    path = evidence / lane['receipt']
    check(path, lane['receiptSHA256'])
    record = read(path)
    # Lane success precedes review/main delivery and cannot complete the cell alone.
    assert record['success'] and record['cellComplete'] is False and len(record['groups']) == 13
    assert all(run['exitCode'] == 0 and not run['timedOut'] and not run['ownedDescendantsRemaining'] for run in record['runs'])
    receipts.append((lane['lane'], record, lane['receiptSHA256']))

fresh = composition['freshProduction']
assert len(fresh) == 69 and all(record['freshProduction'] == fresh for _, record, _ in receipts)
old_fixture = composition['fixtureComparison']['oldSHA256']
current_fixture = composition['fixtureComparison']['currentSHA256']
check(root / 'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift', current_fixture)
old_path = evidence / 'accepted-scoped-native/cs-draft-zero-ruled-native-20261011-v2/FixtureAtFailure.swift'
check(old_path, old_fixture)
old = old_path.read_text()
current = (root / 'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift').read_text()
assert old.split('} else if selected == "depth" {')[0] == current.split('} else if selected == "depth" {')[0]
assert composition['fixtureComparison']['beforeDepthByteIdentical'] and composition['fixtureComparison']['afterDepthByteIdenticalExceptFailureLog']

prerequisite_checks = 0
for name, record, _ in receipts:
    for path, expected in record['checks'].items():
        actual = Path(path)
        if name == 'firstSeven' and actual == root / 'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift':
            assert expected == old_fixture
            actual = old_path
        check(actual, expected)
        prerequisite_checks += 1
    for path, expected in record['freshProduction'].items():
        check(path, expected)

prior = read(root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-DERIVATIVE-LIFT-PLANE-01/integration.json')
premises = dict(prior['sourcePremises'])
updates = {}
for path, expected in fresh.items():
    rel = str(Path(path).relative_to(root))
    if premises.get(rel) != expected:
        updates[rel] = {'before': premises.get(rel), 'after': expected}
    premises[rel] = expected
for rel, expected in premises.items():
    check(root / rel, expected)
    check(integration / rel, expected)
    if args.phase == 'main':
        check(main / rel, expected)

files = manifest['files'] + read(evidence / 'evidence-manifest.json')['files']
for entry in files:
    for target in ([root, integration, main] if args.phase == 'main' else [root, integration]):
        check(target / relative / entry['path'], entry['sha256'])
for name in ('acceptance-manifest.json', 'native-composition.json', 'evidence-manifest.json', 'STOP.md', 'VERIFICATION.md', 'REVIEW.md'):
    expected = digest(evidence / name)
    check(integration / relative / name, expected)
    if args.phase == 'main':
        check(main / relative / name, expected)

protected = read(root / '.build/native-periodic-protected-before.json')
for name, path in [('source', '/private/tmp/cad-di-m4-source-support-20261009'), ('consumer', '/private/tmp/cad-di-m6-consumers-20261009')]:
    path = Path(path)
    snapshot = protected[name]
    assert git(path, 'rev-parse', 'HEAD').decode().strip() == snapshot['head']
    index_path = Path(git(path, 'rev-parse', '--git-path', 'index').decode().strip())
    if not index_path.is_absolute():
        index_path = path / index_path
    check(index_path, snapshot['indexSHA256'])
    assert hashlib.sha256(git(path, 'status', '--porcelain=v1', '-z')).hexdigest() == snapshot['statusSHA256']
    for rel, expected in snapshot['files'].items():
        check(path / rel, expected)
check('/Users/1amageek/.codex/worktrees/source-consumer-handoff-recovery/pending-public-publisher.patch', protected['patchSHA256'])

out = root / '.build' / ('cs-draft-zero-integration-' + args.phase + '.json')
out.write_text(json.dumps(dict(scope='CS-DRAFT-ZERO-RULED-01 and recorded finite-cell definitions only; whole-seven1/7/full87/generalM4-M8 remain open.',
    implementationCommit=args.implementation, phase=args.phase, mainBefore='9c11fd8da7ed484be356d888ddb2c0407219cc98',
    independentCheckout=str(integration), independentHead=args.implementation,
    sourcePremises=premises, premiseUpdates=updates, acceptedScopedReceipts={name: sha for name, _, sha in receipts},
    acceptedPrerequisiteChecks=prerequisite_checks, freshProductionChecks=69*len(receipts), durableEvidenceFiles=len(files),
    evidenceManifestSHA256=digest(evidence/'acceptance-manifest.json'), reviewSHA256=digest(evidence/'REVIEW.md'),
    verificationSHA256=digest(evidence/'VERIFICATION.md'), protectedDrafts=protected, broadRebuild=False, repeatedRuntime=False,
    elapsedSeconds=time.monotonic()-started), indent=2)+'\n')
print(json.dumps(dict(phase=args.phase, sourcePremises=len(premises), prerequisiteChecks=prerequisite_checks,
    freshProductionChecks=69*len(receipts), evidenceFiles=len(files), elapsedSeconds=time.monotonic()-started, output=str(out))))
