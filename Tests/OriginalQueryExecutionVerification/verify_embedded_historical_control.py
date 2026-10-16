#!/usr/bin/env python3
"""Verify one historical Embedded refusal with module-only library inputs."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time
from verify_lineage import ROOT, HERE, BIN, RSS_LIMIT, COMPILE_SECONDS, RUNTIME_SECONDS, digest

HISTORICAL = ROOT / '.build/u1-full-geometry-portable-20261015-r8'
DOCUMENT = HERE / 'Evidence/EmbeddedSwiftLibraries-20261015.json'
DOCUMENT_HASH = 'd5ee66765a73cf3426740e9a19c1e09ef9ff710bc62bf97c8f60fc26e057550b'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--resume-plan', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    fixture = HERE / 'EmbeddedHistoricalClassificationControl.swift'
    if not args.resume_plan:
        output.mkdir(parents=True, exist_ok=False)
        original = HISTORICAL / 'receipt.json'
        prior = json.loads(original.read_text())
        assert prior['sourceCount'] == {'CADCore': 65, 'CADGeometry': 2166}
        compile_phase = next(p for p in prior['phases'] if p['name'] == 'embedded-compile')
        assert compile_phase['exitCode'] == 0 and compile_phase['stopReason'] is None
        historical_sources = {str(HISTORICAL / 'snapshot' / p): h for p, h in prior['sourceSHA256'].items()}
        assert all(digest(p) == h for p, h in historical_sources.items())
        classifier = HISTORICAL / 'snapshot/Sources/CADGeometry/NativeExactGeometricRelations/NativeExactGeometryPublicationFailure.swift'
        assert '@usableFromInline\n    static func resolve(' in classifier.read_text()
        assert digest(DOCUMENT) == DOCUMENT_HASH
        imports = output / 'modules'
        imports.mkdir()
        modules = {p: h for p, h in prior['lanes']['embedded']['compiledProductSHA256'].items() if p.endswith('.swiftmodule')}
        modules.update({p: v['sha256'] for p, v in prior['lanes']['embedded']['dependencies'].items() if p.endswith('.swiftmodule')})
        assert len(modules) == 4
        retained = {}
        for p, h in modules.items():
            assert digest(p) == h
            target = imports / Path(p).name
            shutil.copyfile(p, target)
            retained[str(target)] = h
        saved_fixture = output / fixture.name
        shutil.copyfile(fixture, saved_fixture)
        shutil.copyfile(original, output / 'HistoricalReceipt.json')
        shutil.copyfile(DOCUMENT, output / DOCUMENT.name)
        command = prior['lanes']['embedded']['commands']['link'][:]
        removed = [v for v in command if v.endswith(('.code.o', 'InternalCollectionsUtilities.a', 'HashTreeCollections.a'))]
        assert len(removed) == 4
        command = [v for v in command if v not in removed]
        old_fixture = str(HISTORICAL / 'snapshot/Tests/OriginalQueryExecutionVerification/FullGeometryPortable.swift')
        command[command.index(old_fixture)] = str(saved_fixture)
        for index, value in enumerate(command):
            if value == '-I': command[index + 1] = str(imports)
        executable = output / 'HistoricalControl.wasm'
        command[command.index('-o') + 1] = str(executable)
        runtime = prior['lanes']['embedded']['commands']['runtime'][:]
        runtime[-1] = str(executable)
        receipt = {'status': 'prepared', 'scope': 'Historical r8 classification control only; not current Geometry coverage.',
            'historicalReceipt': {'path': str(output / 'HistoricalReceipt.json'), 'sha256': digest(output / 'HistoricalReceipt.json')},
            'historicalSourceSHA256': prior['sourceSHA256'], 'historicalSnapshotSHA256': historical_sources,
            'historicalClassifierSHA256': digest(classifier), 'resolveClientEmissionPresent': False,
            'compilerVersion': prior['compilerVersion'], 'toolSHA256': prior['toolSHA256'], 'wasmSDK': prior['wasmSDK'],
            'moduleSHA256': retained, 'fixture': {'path': str(saved_fixture), 'sha256': digest(saved_fixture)},
            'runnerSHA256': digest(__file__), 'document': {'path': str(output / DOCUMENT.name), 'sha256': DOCUMENT_HASH},
            'omittedSwiftCodeLinkInputs': removed, 'commands': {'link': command, 'runtime': runtime},
            'wasmStackBytes': 67108864, 'bounds': {'compileLinkSeconds': COMPILE_SECONDS, 'runtimeSeconds': RUNTIME_SECONDS, 'aggregateRSSBytes': RSS_LIMIT}, 'phases': []}
    else:
        receipt = json.loads((output / 'receipt.json').read_text())
    def save():
        receipt['historicalSourceCurrentDrift'] = [p for p, h in receipt['historicalSourceSHA256'].items() if digest(ROOT / p) != h]
        receipt['snapshotDrift'] = [p for p, h in receipt['historicalSnapshotSHA256'].items() if digest(p) != h]
        receipt['moduleDrift'] = [p for p, h in receipt['moduleSHA256'].items() if digest(p) != h]
        assert not receipt['snapshotDrift'] and not receipt['moduleDrift']
        assert digest(receipt['fixture']['path']) == receipt['fixture']['sha256']
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    save()
    if args.prepare_only:
        print('PREPARED historical module-only control; no compiler launched', flush=True)
        return
    assert all(digest(BIN / name) == h for name, h in receipt['toolSHA256'].items())
    sdk = Path(receipt['wasmSDK']['path'])
    assert all(digest(sdk / name) == h for name, h in receipt['wasmSDK']['metadataSHA256'].items())
    receipt['executionRunnerSHA256'] = digest(__file__)
    receipt['environment'] = {'PATHFirst': str(BIN), 'TOOLCHAINS': None}
    receipt['platformArchiveSHA256'] = {v: digest(v) for v in receipt['commands']['link'] if v.endswith('.a')}
    save()
    environment = dict(os.environ)
    environment['PATH'] = str(BIN) + ':' + environment.get('PATH', '')
    environment.pop('TOOLCHAINS', None)
    for name in ['link', 'runtime']:
        start = time.monotonic()
        limit = RUNTIME_SECONDS if name == 'runtime' else COMPILE_SECONDS
        peak = 0
        reason = None
        log = output / (name + '.log')
        with log.open('x') as stream:
            process = subprocess.Popen(receipt['commands'][name], cwd=ROOT, env=environment,
                stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            while process.poll() is None:
                entries = [tuple(map(int, row.split())) for row in subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,rss='], text=True).splitlines()]
                descendants = {process.pid}
                while True:
                    updated = descendants | {pid for pid, parent, rss in entries if parent in descendants}
                    if updated == descendants: break
                    descendants = updated
                rss = sum(rss for pid, parent, rss in entries if pid in descendants) * 1024
                peak = max(peak, rss)
                if time.monotonic() - start > limit: reason = 'timeout'
                if rss > RSS_LIMIT: reason = 'aggregateRSSLimit'
                if reason:
                    for pid in descendants:
                        try: os.kill(pid, signal.SIGTERM)
                        except ProcessLookupError: pass
                    try: process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        for pid in descendants:
                            try: os.kill(pid, signal.SIGKILL)
                            except ProcessLookupError: pass
                        process.wait()
                    break
                time.sleep(.5)
        phase = {'name': name, 'command': receipt['commands'][name], 'exitCode': process.returncode,
            'elapsedSeconds': time.monotonic() - start, 'peakRSSBytes': peak,
            'rssScope': 'sampled PPID-descendant process tree', 'wallLimitSeconds': limit,
            'stopReason': reason, 'log': str(log), 'logSHA256': digest(log)}
        receipt['phases'].append(phase)
        save()
        print(json.dumps(phase), flush=True)
        if process.returncode or reason:
            receipt['status'] = 'failed'
            save()
            raise SystemExit(1)
        if name == 'link': receipt['executableSHA256'] = digest(output / 'HistoricalControl.wasm')
    assert 'PASS historical module-only control: real admissionRejected retains resourceLimit(work), kernel resourceLimitExceeded, and work axis' in (output / 'runtime.log').read_text()
    receipt['status'] = 'passed-historical-control'
    save()


if __name__ == '__main__':
    main()
