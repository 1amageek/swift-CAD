#!/usr/bin/env python3
"""Audit one admitted boundary cell, then deliver its exact commit to main."""
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

root = Path('/private/tmp/cad-m4-m8-completion-20261010')
integration = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
main = Path('/Users/1amageek/Desktop/3D/swift-CAD')
relative = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/B-NATIVE-COLLAPSED-CLOSED-01')
evidence = root / relative
implementation = sys.argv[1]
baseline = 'd5fbba40a836e288d458c527c76d92ebf46fd281'
started = time.monotonic()
cache = {}


def git(path, *args):
    return subprocess.check_output(['git', *args], cwd=path, timeout=30)


def read(path):
    return json.loads(Path(path).read_text())


def digest(path):
    path = Path(path)
    before = path.stat()
    key = (str(path), before.st_size, before.st_mtime_ns, before.st_ino)
    if key in cache:
        return cache[key]
    assert time.monotonic() - started < 180, 'audit wall bound'
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


def exact_head(path, head):
    assert git(path, 'rev-parse', 'HEAD').decode().strip() == head
    assert not git(path, 'status', '--porcelain=v1', '-z')


def protected_check(snapshot):
    for name, path in [('source', '/private/tmp/cad-di-m4-source-support-20261009'), ('consumer', '/private/tmp/cad-di-m6-consumers-20261009')]:
        path = Path(path)
        record = snapshot[name]
        assert git(path, 'rev-parse', 'HEAD').decode().strip() == record['head']
        index = Path(git(path, 'rev-parse', '--git-path', 'index').decode().strip())
        check(index if index.is_absolute() else path / index, record['indexSHA256'])
        assert hashlib.sha256(git(path, 'status', '--porcelain=v1', '-z')).hexdigest() == record['statusSHA256']
        for rel, sha in record['files'].items():
            check(path / rel, sha)
    check('/Users/1amageek/.codex/worktrees/source-consumer-handoff-recovery/pending-public-publisher.patch', snapshot['patchSHA256'])


exact_head(root, implementation)
exact_head(integration, implementation)
exact_head(main, baseline)
summary = read(evidence / 'summary.json')
manifest = read(evidence / 'evidence-manifest.json')
prior = read(root / 'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-DRAFT-ZERO-RULED-01/integration.json')
premises = dict(prior['sourcePremises'])
fresh = None
references = 0
lane_receipts = {}
updates = {}
for lane, metadata in summary['lanes'].items():
    path = evidence / metadata['receipt']
    check(path, metadata['receiptSHA256'])
    record = read(path)
    assert record['state'] == 'complete-collapsed-boundary-cell-verified'
    module_path = path.parent / 'module-dependency/module-receipt.json'
    check(module_path, metadata['moduleReceiptSHA256'])
    module = read(module_path)
    assert len(record['freshProduction']) == 32 and record['freshProduction'] == module['freshProduction']
    if fresh is None:
        fresh = record['freshProduction']
    assert record['freshProduction'] == fresh
    for data, log_root in [(record, path.parent), (module, module_path.parent)]:
        for key in ['checks', 'products', 'freshProduction']:
            for name, sha in data[key].items():
                check(name, sha)
                references += 1
        for run in data['runs']:
            assert run['exitCode'] == 0 and not run['timedOut']
            check(log_root / (run['label'] + '.log'), run['logSHA256'])
    lane_receipts[lane] = {'path': str(path.relative_to(root)), 'sha256': metadata['receiptSHA256'], 'moduleSHA256': metadata['moduleReceiptSHA256']}
    for name, sha in record['freshProduction'].items():
        rel = str(Path(name).relative_to(root))
        if premises.get(rel) != sha:
            updates[rel] = {'before': premises.get(rel), 'after': sha}
        premises[rel] = sha

inputs = ['PROGRESS.md', 'Sources/CADGeometry/OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md',
    'Tests/OriginalPublicAcceptanceVerification/NativeCollapsedBoundaryAcceptance.swift',
    'Tests/OriginalPublicAcceptanceVerification/NativeCollapsedBoundaryAcceptance.py']
changed = {rel: digest(root / rel) for rel in inputs}
files = {str(relative / rel): sha for rel, sha in manifest['files'].items()}
for name in ['evidence-manifest.json', 'summary.json', 'REVIEW.md']:
    files[str(relative / name)] = digest(evidence / name)
for rel, sha in {**premises, **changed, **files}.items():
    check(root / rel, sha)
    check(integration / rel, sha)
protected = read(root / '.build/native-periodic-protected-before.json')
protected_check(protected)
independent_seconds = time.monotonic() - started

# Main changes only after every admitted independent comparison has passed.
result = subprocess.run(['git', 'merge', '--ff-only', '--quiet', implementation], cwd=main, capture_output=True, timeout=60)
assert result.returncode == 0, result.stderr.decode()
exact_head(main, implementation)
for rel, sha in {**premises, **changed, **files}.items():
    check(main / rel, sha)
protected_check(protected)
out = root / '.build/native-collapsed-main-integration.json'
out.write_text(json.dumps(dict(scope='B-NATIVE-COLLAPSED-CLOSED-01 and finite mapping definitions only; generalM4-M8/whole-seven1/7/full87 remain open.',
    implementationCommit=implementation, mainBefore=baseline, mainHead=implementation,
    mainDeliveryMode='normal fast-forward after independent admitted comparison', independentCheckout=str(integration),
    sourcePremises=premises, premiseUpdates=updates, changedInputs=changed, acceptedScopedReceipts=lane_receipts,
    prerequisiteReferences=references, freshProductionChecks=32*4, durableEvidenceFiles=len(files),
    evidenceManifestSHA256=digest(evidence/'evidence-manifest.json'), reviewSHA256=digest(evidence/'REVIEW.md'),
    verificationSHA256=digest(evidence/'VERIFICATION.md'), protectedDrafts=protected,
    independentSeconds=independent_seconds, totalSeconds=time.monotonic()-started,
    broadRebuild=False, repeatedRuntime=False, uniqueHashComparisons=len(cache)), indent=2)+'\n')
print(json.dumps(dict(sourcePremises=len(premises), prerequisiteReferences=references,
    freshProductionChecks=128, evidenceFiles=len(files), mainHead=implementation,
    elapsedSeconds=time.monotonic()-started, output=str(out))))
