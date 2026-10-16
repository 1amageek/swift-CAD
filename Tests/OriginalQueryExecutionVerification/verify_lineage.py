#!/usr/bin/env python3
"""Compile the pinned complete Core and execute canonical-lineage behavior on three lanes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BIN = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin')
SWIFTC = BIN / 'swiftc'
MACSDK = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')
SDKBASE = Path('/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1')
LD = Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld')
NATIVE_RECEIPT = ROOT / '.build/u1-native-core-lineage-20261015/receipt.json'
NATIVE_TEST_RECEIPT = ROOT / '.build/u1-lineage-native-tests-20261015/receipt.json'
PRODUCT_RECEIPTS = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence/G01-SPHERE-CONE-FINITE-UV'
ACCEPTED = ROOT / '.build/g01-finite-bounded-20261014/accepted'
RSS_LIMIT = 10 * 1024**3
COMPILE_SECONDS = 1200
RUNTIME_SECONDS = 120


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--lanes', nargs='+', choices=['asan', 'wasm', 'embedded'], default=['asan', 'wasm', 'embedded'])
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ)
    environment['PATH'] = str(BIN) + ':' + environment.get('PATH', '')
    environment.pop('TOOLCHAINS', None)
    environment['ASAN_OPTIONS'] = 'halt_on_error=1:abort_on_error=1'
    os.chdir(ROOT)
    production = json.loads(NATIVE_RECEIPT.read_text())
    current = sorted((ROOT / 'Sources/CADCore').rglob('*.swift'))
    source_hashes = {str(p.relative_to(ROOT)): digest(p) for p in current}
    assert source_hashes == production['sourceSHA256'], 'Full Core differs from the accepted native lineage snapshot'
    sources = []
    pinned_hashes = {}
    inputs = current + [HERE / 'LineageCanonicalPortable.swift', Path(__file__).resolve(),
        ROOT / 'Tests/CADCoreTests/TopologyLineageCanonicalTests.swift', ROOT / 'Sources/CADCore/DESIGN.md',
        HERE / 'verify.py', ROOT / 'Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs']
    input_hashes = {str(p.relative_to(ROOT)): digest(p) for p in inputs}
    for path in inputs:
        copied = output / 'snapshot' / path.relative_to(ROOT)
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, copied)
        pinned_hashes[str(copied)] = digest(copied)
        if path in current:
            sources.append(copied)
    fixture = output / 'snapshot/Tests/OriginalQueryExecutionVerification/LineageCanonicalPortable.swift'
    wasi_runner = output / 'snapshot/Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs'
    receipt = {
        'scope': 'Actual complete CADCore canonical lineage only; no BRep or whole-U1 completion claim.',
        'sourceCount': len(current), 'sourceSHA256': source_hashes, 'inputSHA256': input_hashes,
        'snapshotSHA256': pinned_hashes, 'compiler': str(SWIFTC),
        'toolSHA256': {name: digest(BIN / name) for name in ['swiftc', 'swift-frontend', 'clang']},
        'nativeLinker': {'path': str(LD), 'sha256': digest(LD)},
        'nativeSDK': {'path': str(MACSDK), 'SDKSettings.json': digest(MACSDK / 'SDKSettings.json')},
        'wasmSDK': {'path': str(SDKBASE), 'identifiers': ['swift-6.4.0-RELEASE_wasm', 'swift-6.4.0-RELEASE_wasm-embedded'],
            'metadataSHA256': {name: digest(SDKBASE / name) for name in ['swift-sdk.json', 'embedded-swift-sdk.json', 'toolset.json', 'embedded-toolset.json']}},
        'acceptedNativeReceiptSHA256': digest(NATIVE_RECEIPT),
        'acceptedNativeTestReceiptSHA256': digest(NATIVE_TEST_RECEIPT),
        'bounds': {'compileAndLinkPerLaneSeconds': COMPILE_SECONDS, 'runtimeSeconds': RUNTIME_SECONDS,
            'aggregateRSSBytes': RSS_LIMIT, 'compilerProcessesAtOnce': 1},
        'environment': {'PATHFirst': str(BIN), 'TOOLCHAINS': None, 'ASAN_OPTIONS': environment['ASAN_OPTIONS']},
        'phases': [], 'lanes': {}, 'status': 'running'}

    def save():
        observed = {str(p.relative_to(ROOT)): digest(p) for p in inputs}
        receipt['currentDrift'] = [path for path, value in input_hashes.items() if observed[path] != value]
        receipt['snapshotDrift'] = [path for path, value in pinned_hashes.items() if digest(path) != value]
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(name, command, seconds):
        log = output / (name + '.log')
        started = time.monotonic()
        peak = 0
        reason = None
        save()
        with log.open('x') as stream:
            process = subprocess.Popen([str(v) for v in command], cwd=ROOT, env=environment,
                stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            while process.poll() is None:
                rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,rss='], text=True)
                entries = [tuple(map(int, row.split())) for row in rows.splitlines()]
                ids = {process.pid}
                while True:
                    children = ids | {pid for pid, parent, rss in entries if parent in ids}
                    if children == ids:
                        break
                    ids = children
                rss = sum(rss for pid, parent, rss in entries if pid in ids) * 1024
                peak = max(peak, rss)
                if time.monotonic() - started > seconds:
                    reason = 'timeout'
                if rss > RSS_LIMIT:
                    reason = 'aggregateRSSLimit'
                if reason:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    break
                time.sleep(.1)
        phase = {'name': name, 'command': [str(v) for v in command], 'exitCode': process.returncode,
            'seconds': time.monotonic() - started, 'sampledPeakProcessTreeRSSBytes': peak,
            'stopReason': reason, 'wallLimitSeconds': seconds, 'log': str(log), 'logSHA256': digest(log)}
        receipt['phases'].append(phase)
        save()
        print(json.dumps({key: phase[key] for key in ['name', 'exitCode', 'seconds', 'sampledPeakProcessTreeRSSBytes', 'stopReason']}), flush=True)
        if process.returncode or reason or receipt['currentDrift'] or receipt['snapshotDrift']:
            receipt['status'] = 'failed'
            save()
            raise SystemExit(1)
        return log

    started = time.monotonic()
    version_log = run('compiler-version', [SWIFTC, '--version'], 30)
    receipt['compilerVersion'] = version_log.read_text()
    node_log = run('node-version', ['/usr/local/bin/node', '--version'], 30)
    receipt['nodeVersion'] = node_log.read_text()
    for lane in args.lanes:
        lane_started = time.monotonic()
        destination = output / lane
        destination.mkdir()
        dependencies = destination / 'dependencies'
        dependencies.mkdir()
        prior_path = PRODUCT_RECEIPTS / lane / 'products.json'
        prior = json.loads(prior_path.read_text())
        dependency_hashes = {}
        objects = []
        for module in ['InternalCollectionsUtilities', 'HashTreeCollections']:
            for extension in ['.swiftmodule', '.a' if lane == 'embedded' else '.o']:
                artifact = ACCEPTED / lane / (module + extension)
                value = digest(artifact)
                assert prior[str(artifact)] == value, 'Dependency differs from its accepted receipt'
                target = dependencies / artifact.name
                shutil.copyfile(artifact, target)
                dependency_hashes[str(target)] = {'source': str(artifact), 'sha256': value}
                if extension != '.swiftmodule':
                    objects.append(target)
        lane_receipt = {'dependencyReceipt': str(prior_path), 'dependencyReceiptSHA256': digest(prior_path),
            'dependencies': dependency_hashes}
        receipt['lanes'][lane] = lane_receipt
        flags = ['-parse-as-library', '-Onone', '-g', '-swift-version', '6', '-package-name', 'swift_cad',
            '-whole-module-optimization', '-num-threads', '0', '-j1', '-enable-testing',
            '-I', destination, '-I', dependencies]
        if lane == 'asan':
            flags += ['-sanitize=address', '-sdk', MACSDK, '-target', 'arm64-apple-macos27.0',
                '-tools-directory', BIN, '-Xclang-linker', '-fuse-ld=' + str(LD)]
            lane_receipt['sdkIdentifier'] = 'macOS27.0'
        else:
            flags += ['-target', 'wasm32-unknown-wasip1', '-sdk', SDKBASE / 'WASI.sdk',
                '-resource-dir', SDKBASE / ('swift.xctoolchain/usr/lib/swift' if lane == 'embedded' else 'swift.xctoolchain/usr/lib/swift_static'),
                '-static-stdlib', '-tools-directory', BIN, '-Xclang-linker', '-resource-dir', '-Xclang-linker',
                SDKBASE / 'swift.xctoolchain/usr/lib/swift_static/clang']
            lane_receipt['sdkIdentifier'] = 'swift-6.4.0-RELEASE_wasm' + ('-embedded' if lane == 'embedded' else '')
        if lane == 'embedded':
            flags += ['-enable-experimental-feature', 'Embedded']
        module = destination / 'CADCore.swiftmodule'
        object_file = destination / 'CADCore.code.o'
        command = [SWIFTC] + flags + ['-module-name', 'CADCore', '-emit-module', '-emit-module-path', module,
            '-emit-object', '-o', object_file] + sources
        run(lane + '-Core-compile', command, max(1, COMPILE_SECONDS - (time.monotonic() - lane_started)))
        lane_receipt['compiledProducts'] = {str(path): digest(path) for path in [module, object_file]}
        executable = destination / ('LineageCanonical.wasm' if lane != 'asan' else 'LineageCanonical')
        command = [SWIFTC] + flags + [fixture, object_file] + objects + ['-o', executable]
        if lane == 'embedded':
            unicode = SDKBASE / 'swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a'
            command += ['-Xlinker', unicode, '-Xlinker', '-lc++', '-Xlinker', '-lc++abi', '-Xlinker', '-lswift_Concurrency']
            lane_receipt['unicodeLibrarySHA256'] = digest(unicode)
        run(lane + '-link', command, max(1, COMPILE_SECONDS - (time.monotonic() - lane_started)))
        lane_receipt['executable'] = {'path': str(executable), 'sha256': digest(executable), 'bytes': executable.stat().st_size}
        runtime = [executable] if lane == 'asan' else ['/usr/local/bin/node', wasi_runner, executable]
        log = run(lane + '-runtime', runtime, RUNTIME_SECONDS)
        expected = ['PASS canonical construction:', 'PASS invalid canonical input:', 'PASS COW lifetime:',
            'PASS lineage canonical portable: 3 oracle groups']
        assert all(value in log.read_text() for value in expected), 'Runtime did not execute all actual lineage oracles'
        lane_receipt['oracleGroups'] = 3
        lane_receipt['elapsedSeconds'] = time.monotonic() - lane_started
        save()
    receipt['status'] = 'passed'
    receipt['elapsedSeconds'] = time.monotonic() - started
    save()
    assert not receipt['currentDrift'] and not receipt['snapshotDrift']
    print('PASS lineage canonical full Core: ' + ', '.join(args.lanes) + '; drift=0', flush=True)


if __name__ == '__main__':
    main()
