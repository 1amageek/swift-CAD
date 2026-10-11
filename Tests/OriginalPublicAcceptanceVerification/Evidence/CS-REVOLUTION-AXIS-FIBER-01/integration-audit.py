#!/usr/bin/env python3
"""Compare this frozen cell and its admitted premises, then normally fast-forward main."""
import hashlib
import json
import subprocess
import time
from pathlib import Path

ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
INDEPENDENT = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
MAIN = Path('/Users/1amageek/Desktop/3D/swift-CAD')
BASE = 'aac3e92a12ad1a9fa48cbb7980508396afe1ce05'
IMPLEMENTATION = '11f4e9fd307a68f845b6c30374b124db8261b7d2'
RELATIVE = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/CS-REVOLUTION-AXIS-FIBER-01')
EVIDENCE = ROOT / RELATIVE
started = time.monotonic()
cache, references = {}, 0


def require(value, message):
    if not value:
        raise RuntimeError(message)


def git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root, timeout=30)


def read(path):
    return json.loads(Path(path).read_text())


def sha(path):
    path = Path(path)
    before = path.stat()
    key = (str(path), before.st_size, before.st_mtime_ns, before.st_ino)
    if key not in cache:
        require(time.monotonic() - started < 120, 'audit wall bound')
        cache[key] = hashlib.sha256(path.read_bytes()).hexdigest()
        after = path.stat()
        require((before.st_size, before.st_mtime_ns, before.st_ino) ==
                (after.st_size, after.st_mtime_ns, after.st_ino), 'changed while hashing: ' + str(path))
    return cache[key]


def check(path, expected):
    global references
    require(sha(path) == expected, 'SHA mismatch: ' + str(path))
    references += 1


for root, head in [(ROOT, IMPLEMENTATION), (INDEPENDENT, BASE), (MAIN, BASE)]:
    require(git(root, 'rev-parse', 'HEAD').decode().strip() == head, 'HEAD: ' + str(root))
    require(not git(root, 'status', '--porcelain=v1', '-z'), 'dirty checkout: ' + str(root))
require(git(MAIN, 'branch', '--show-current').decode().strip() == 'main', 'main branch')
subprocess.run(['git', 'merge', '--ff-only', IMPLEMENTATION], cwd=INDEPENDENT,
               check=True, timeout=30, stdout=subprocess.DEVNULL)

prior_path = Path('Tests/OriginalPublicAcceptanceVerification/Evidence/S-RULED-CLOSED-GUIDE-SEAM-01/integration.json')
prior = read(ROOT / prior_path)
require(hashlib.sha256(git(ROOT, 'show', str(BASE) + ':' + str(prior_path))).hexdigest()
        == sha(ROOT / prior_path), 'inherited integration changed')
summary_path = EVIDENCE / 'acceptance/summary.json'
check(summary_path, 'c8d15d9953ecf32304279b89e081621cc9d2961a1283dec8df7e5843cb160aa3')
summary = read(summary_path)
require(summary['cell'] == 'CS-REVOLUTION-AXIS-FIBER-01', 'cell')
require(summary['cellComplete'] is False, 'raw verification status')
fresh = {name: metadata['sha256'] for name, metadata in summary['freshProduction29'].items()}
require(len(fresh) == 29, 'production body count')
for name, metadata in summary['freshProduction29'].items():
    check(name, metadata['sha256'])
    check(EVIDENCE / metadata['bytes'], metadata['sha256'])
sources = dict(prior['sourcePremises'])
for name, digest in fresh.items():
    sources[str(Path(name).relative_to(ROOT))] = digest
for name, digest in sources.items():
    check(ROOT / name, digest)
    check(INDEPENDENT / name, digest)

check(EVIDENCE / 'manifest.json', '9e631c947ea172d5c583ae872f7b40dce26bc094897d711e22981025b62058a2')
durable = {}
for name, digest in read(EVIDENCE / 'manifest.json')['files'].items():
    check(EVIDENCE / name, digest)
    check(INDEPENDENT / RELATIVE / name, digest)
    durable[str(RELATIVE / name)] = digest
for name in ['manifest.json', 'REVIEW.md', 'VERIFICATION.md']:
    digest = sha(EVIDENCE / name)
    check(INDEPENDENT / RELATIVE / name, digest)
    durable[str(RELATIVE / name)] = digest

groups = {lane: set() for lane in ['native', 'asan', 'wasm', 'embedded']}
for metadata in summary['accepted']:
    receipt_path = EVIDENCE / metadata['receipt']
    check(receipt_path, metadata['receiptSHA256'])
    record = read(receipt_path)
    require(record['success'] and record['postHashesMatch'], 'accepted receipt status')
    require(record['freshProduction'] == fresh, 'accepted production mismatch')
    require(not groups[metadata['lane']].intersection(metadata['groups']), 'duplicate groups')
    groups[metadata['lane']].update(metadata['groups'])
    comparators = {(name, item['sha256']): Path(item['path'])
                   for name, item in record.get('historicalComparators', {}).items()}
    for field, filename in [('fixture', 'RevolutionAxisFiberAcceptance.swift'),
                            ('helper', 'RevolutionAxisFiberOracle.swift'),
                            ('runner', 'RevolutionAxisFiberAcceptance.py')]:
        item = metadata[field]
        check(EVIDENCE / item['bytes'], item['sha256'])
        comparators[(str(ROOT / 'Tests/OriginalPublicAcceptanceVerification' / filename),
                     item['sha256'])] = EVIDENCE / item['bytes']
    for name, digest in record['checks'].items():
        check(comparators.get((name, digest), Path(name)), digest)
    check(metadata['product']['originalPath'], metadata['product']['sha256'])
    require(read(receipt_path.parent / 'compile-command.json') == record['runs'][0]['command'],
            'compiler command')
    for item in read(receipt_path.parent / 'compiler-inputs.json').values():
        check(EVIDENCE / item['bytes'], item['sha256'])
    require({run['label'] for run in record['runs']} ==
            {'compile-link', *('runtime-' + group for group in metadata['groups'])}, 'run groups')
    for run, saved in zip(record['runs'], metadata['runs'], strict=True):
        require(run['label'] == saved['label'] and run['exitCode'] == 0 and not run['timedOut'], 'run status')
        require(not run['ownedDescendantsRemaining'] and run['elapsedSeconds'] < 120, 'run bound')
        check(EVIDENCE / saved['log'], run['logSHA256'])
        require(saved['logSHA256'] == run['logSHA256'], 'saved log binding')
expected = {'complete', 'empty', 'resources', 'cancel-entry', 'cancel-final', 'cancel-empty', 'lifetime'}
require(all(value == expected for value in groups.values()), 'four-lane complete groups')

protected = prior['protectedDrafts']
for name, directory in [('source', '/private/tmp/cad-di-m4-source-support-20261009'),
                        ('consumer', '/private/tmp/cad-di-m6-consumers-20261009')]:
    directory = Path(directory)
    record = protected[name]
    require(git(directory, 'rev-parse', 'HEAD').decode().strip() == record['head'], 'protected HEAD')
    index = Path(git(directory, 'rev-parse', '--git-path', 'index').decode().strip())
    check(index if index.is_absolute() else directory / index, record['indexSHA256'])
    require(hashlib.sha256(git(directory, 'status', '--porcelain=v1', '-z')).hexdigest()
            == record['statusSHA256'], 'protected status')
    for relative, digest in record['files'].items():
        check(directory / relative, digest)
check('/Users/1amageek/.codex/worktrees/source-consumer-handoff-recovery/pending-public-publisher.patch',
      protected['patchSHA256'])

subprocess.run(['git', 'merge', '--ff-only', IMPLEMENTATION], cwd=MAIN,
               check=True, timeout=30, stdout=subprocess.DEVNULL)
result = dict(cell=summary['cell'], finiteCellVerified=True, implementationCommit=IMPLEMENTATION,
              mainBefore=BASE, mainHead=IMPLEMENTATION, mainDeliveryMode='normal fast-forward',
              independentCheckout=str(INDEPENDENT), rawVerificationCellComplete=False,
              inheritedIntegration=str(prior_path), inheritedIntegrationSHA256=sha(ROOT / prior_path),
              sourcePremises=sources, durableEvidence=durable, protectedDrafts=protected,
              auditReferences=references, uniqueArtifacts=len(cache), elapsedSeconds=time.monotonic()-started,
              auditScriptSHA256=sha(__file__), buildOrRuntimeRepeated=False,
              wholeSevenComplete='1/7', full87Complete=False, allM4M8Complete=False)
output = ROOT / '.build/revolution-axis-main-integration.json'
output.write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({key: result[key] for key in ['cell','implementationCommit','mainHead','auditReferences',
                                             'uniqueArtifacts','elapsedSeconds']}))
