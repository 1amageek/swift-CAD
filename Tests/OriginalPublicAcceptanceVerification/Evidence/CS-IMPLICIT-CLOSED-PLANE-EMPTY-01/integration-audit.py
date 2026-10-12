#!/usr/bin/env python3
"""Read-only delivery audit. Behavioral acceptance belongs to the frozen packet/review."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path('/private/tmp/cad-m4-m8-completion-20261010')
INDEPENDENT = Path('/private/tmp/cad-m4-ds-main-integration-20261010')
MAIN = Path('/Users/1amageek/Desktop/3D/swift-CAD')
CELL = 'CS-IMPLICIT-CLOSED-PLANE-EMPTY-01'
REL = Path('Tests/OriginalPublicAcceptanceVerification/Evidence') / CELL
SUMMARY = 'd434922e6db74bf21baa7f1e4ab7fdf2c27c41a17bf5d2442df2b303f86681b7'
MANIFEST = '126b6fd82a9db95b8f019e3a72b46d02840703ad0bcbaf1ccd257aa9b5d8006a'
GROUPS = {'complete', 'dispatch', 'source', 'requests', 'resources', 'readmission',
          'cancel-entry', 'cancel-final', 'cancel-reader', 'lifetime', 'changed-controls'}

def require(value, message):
    if not value:
        raise RuntimeError(message)

def git(directory, *args):
    return subprocess.check_output(['git', *args], cwd=directory, timeout=30)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('implementation')
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--review-sha256', required=True)
    args = parser.parse_args()
    require(git(ROOT, 'rev-parse', 'HEAD').decode().strip() == args.implementation, 'root HEAD')
    require(git(INDEPENDENT, 'rev-parse', 'HEAD').decode().strip() == args.implementation, 'independent HEAD')
    require(git(MAIN, 'rev-parse', 'HEAD').decode().strip() == args.baseline, 'main moved')
    for tree in [ROOT, INDEPENDENT, MAIN]:
        require(not git(tree, 'status', '--porcelain=v1'), 'dirty delivery tree: ' + str(tree))
    git(ROOT, 'merge-base', '--is-ancestor', args.baseline, args.implementation)
    require(git(ROOT, 'branch', '--show-current').decode().strip() == 'codex/m4-m8-completion', 'root branch')
    require(git(MAIN, 'branch', '--show-current').decode().strip() == 'main', 'main branch')
    files = {}
    def checked(relative, expected):
        relative = Path(relative)
        require(not relative.is_absolute() and '..' not in relative.parts, 'unsafe evidence path')
        if str(relative) not in files:
            content = (ROOT / relative).read_bytes()
            require(digest(content) == expected, 'root digest: ' + str(relative))
            require((INDEPENDENT / relative).read_bytes() == content, 'independent bytes: ' + str(relative))
            files[str(relative)] = expected
        else:
            require(files[str(relative)] == expected, 'conflicting digest')
        return (ROOT / relative).read_bytes()
    summary = json.loads(checked(REL / 'acceptance/summary.json', SUMMARY))
    manifest = json.loads(checked(REL / 'acceptance/manifest.json', MANIFEST))
    checked(REL / 'REVIEW.md', args.review_sha256)
    for entry in manifest['files'].values():
        checked(entry['path'], entry['sha256'])
    require(summary['cell'] == CELL and len(summary['freshProduction']) == 66, 'wrong cell/production count')
    require(set(summary['laneSet']) == {'native', 'asan', 'wasm', 'embedded'}, 'lane set')
    require(set(summary['groups']) == GROUPS and summary['scope']['runtimeCount'] == 44, 'group set')
    lanes = {lane: set() for lane in summary['laneSet']}
    for part in summary['accepted']:
        require(part['rawSuccess'] and part['preAndPostAdmissionPassed'], 'rejected part adopted')
        lane = part['lane']
        require(not lanes[lane].intersection(part['groups']), 'duplicate runtime adoption')
        lanes[lane].update(part['groups'])
        for run in part['runs']:
            require(run['exitCode'] == 0 and not run.get('boundedStop'), 'failed accepted run')
            require(not run.get('ownedDescendantsRemaining'), 'remaining process')
    require(all(groups == GROUPS for groups in lanes.values()), 'incomplete lane')
    require(len(summary['compiledBindings']) == 66, 'compiled body count')
    for binding in summary['compiledBindings']:
        original = binding['original']; compiled = binding['compiledInput']
        body = checked(original['path'], original['sha256'])
        product = checked(compiled['path'], compiled['sha256'])
        relative = Path(binding['originalPath']).relative_to(ROOT)
        checked(relative, original['sha256'])
        require(product.endswith(body), 'compiled body suffix')
        require(digest(product[:-len(body)]) == binding['prefixSHA256'], 'compiled prefix')
    changed = git(ROOT, 'diff', '--name-only', args.baseline, args.implementation).decode().splitlines()
    for relative in changed:
        content = (ROOT / relative).read_bytes()
        require(git(ROOT, 'show', args.implementation + ':' + relative) == content, 'uncommitted delivery bytes')
        require((INDEPENDENT / relative).read_bytes() == content, 'independent delivery change')
    protected = Path('/Users/1amageek/.codex/worktrees/source-consumer-handoff-recovery/pending-public-publisher.patch')
    require(digest(protected.read_bytes()) == '97db4b01b16d6c5a66cdd0bfdfbeda4aa939389f12481b2e0ba8d10d873e8016', 'protected draft')
    print(json.dumps(dict(cell=CELL, success=True, implementation=args.implementation,
        baseline=args.baseline, summarySHA256=SUMMARY, manifestSHA256=MANIFEST,
        reviewSHA256=args.review_sha256, durableFilesChecked=len(files), freshBodiesChecked=66,
        acceptedRuntimeGroups=44, changedPathsChecked=len(changed), build=0, runtime=0,
        protectedDraftUnchanged=True, pushPerformed=False), indent=2))

if __name__ == '__main__':
    main()
