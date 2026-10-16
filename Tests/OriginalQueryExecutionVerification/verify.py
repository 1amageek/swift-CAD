"""Build and execute the real focused Core/Geometry closure against verified L0 products."""
import argparse
import hashlib
import json
import os
import pathlib
import signal
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
TOOLBIN = pathlib.Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin')
SWIFTC = TOOLBIN / 'swiftc'
SDKBASE = pathlib.Path('/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1')
LOWER = ROOT / '.build/u1-direct-lower-portable-native-backend-20261015-023900'
MACSDK = pathlib.Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(paths):
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(set(paths))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--reuse-production')
    parser.add_argument('--lanes', nargs='+', choices=['native', 'asan', 'wasm', 'embedded'],
                        default=['native', 'asan', 'wasm', 'embedded'])
    args = parser.parse_args()
    output = pathlib.Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.chdir(ROOT)
    environment = dict(os.environ, PATH=str(TOOLBIN) + ':' + os.environ['PATH'])
    core = [ROOT / path for path in (HERE / 'CoreSources.txt').read_text().splitlines()]
    geometry = [ROOT / path for path in (HERE / 'GeometrySources.txt').read_text().splitlines()]
    fixtures = [ROOT / 'Tests/OriginalPublicAcceptanceVerification/OriginalQueryExecutionAcceptance.swift',
                HERE / 'FocusedFixtures.swift']
    inputs = core + geometry + fixtures + list(HERE.glob('*.txt')) + [pathlib.Path(__file__).resolve()]
    inputs += [ROOT / 'Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs']
    frozen = hashes(inputs)
    lower_inputs = json.loads((LOWER / 'sources-before.json').read_text())
    assert all(digest(ROOT / path) == expected for path, expected in lower_inputs.items()), 'Lower source receipt mismatch'
    prior = json.loads((LOWER / 'receipt.json').read_text())
    summary = json.loads((LOWER / 'verification-summary.json').read_text())
    receipt = {'scope': 'Actual 27 Core and 63 Geometry files; common execution/predicates only, no whole-package or Kernel claim.',
               'sourceHashes': frozen, 'lowerSourceHashes': lower_inputs,
               'lowerReceiptSHA256': digest(LOWER / 'receipt.json'), 'phases': [], 'lanes': {},
               'compiler': str(SWIFTC), 'compilerSHA256': digest(SWIFTC.resolve()),
               'frontendSHA256': digest(TOOLBIN / 'swift-frontend'),
               'clangSHA256': digest(TOOLBIN / 'clang'),
               'wasmSDKMetadata': {
                   'swift-sdk.json': digest(SDKBASE / 'swift-sdk.json'),
                   'embedded-toolset.json': digest(SDKBASE / 'embedded-toolset.json'),
                   'toolset.json': digest(SDKBASE / 'toolset.json')},
               'nodeVersion': subprocess.check_output(['/usr/local/bin/node', '--version'], text=True),
               'compilerVersion': subprocess.check_output([SWIFTC, '--version'], text=True, env=environment),
               'limitations': 'WASI cooperative tasks do not prove multi-threaded WASM locking.'}

    def save():
        receipt['sourcesUnchanged'] = frozen == hashes(inputs)
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2))

    def run(name, command, seconds):
        log = output / (name + '.log')
        started = time.monotonic()
        peak = 0
        reason = None
        save()
        with log.open('x') as stream:
            process = subprocess.Popen([str(value) for value in command], stdout=stream,
                stderr=subprocess.STDOUT, env=environment, start_new_session=True)
            while process.poll() is None:
                time.sleep(.5)
                entries = [tuple(map(int, row.split())) for row in
                    subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss='], text=True).splitlines()]
                ids = {process.pid}
                while True:
                    updated = ids | {pid for pid, parent, rss in entries if parent in ids}
                    if updated == ids:
                        break
                    ids = updated
                rss = sum(rss for pid, parent, rss in entries if pid in ids) * 1024
                peak = max(peak, rss)
                if time.monotonic() - started > seconds:
                    reason = 'timeout'
                if rss > 10 * 1024 ** 3:
                    reason = 'aggregateRSSLimit'
                if reason:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(2)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    break
        record = {'name': name, 'command': [str(value) for value in command],
            'exitCode': process.returncode, 'seconds': time.monotonic() - started,
            'peakAggregateRSSBytes': peak, 'stopReason': reason,
            'log': str(log), 'logSHA256': digest(log)}
        receipt['phases'].append(record)
        save()
        print(json.dumps({key: record[key] for key in ["name", "exitCode", "seconds", "peakAggregateRSSBytes", "stopReason"]}), flush=True)
        if process.returncode or reason or not receipt['sourcesUnchanged']:
            raise SystemExit(1)

    for lane in args.lanes:
        lane_started = time.monotonic()
        destination = output / lane
        destination.mkdir()
        architecture = 'wasm32-unknown-wasip1' if lane in ('wasm', 'embedded') else 'arm64-apple-macosx'
        lower_products = LOWER / lane / architecture / 'debug'
        modules = lower_products / 'Modules'
        recorded_modules = summary['linkedL0Modules'][lane]
        for path, expected in recorded_modules.items():
            assert digest(ROOT / path) == expected, 'Lower module receipt mismatch'
        phase = next(value for value in reversed(prior['phases'])
            if value['name'].startswith(lane + '-scope-compile') and value['exitCode'] == 0)
        objects = [ROOT / value['path'] for value in phase['linkedL0Objects']]
        assert all(digest(ROOT / value['path']) == value['sha256'] for value in phase['linkedL0Objects']), 'Lower object receipt mismatch'
        receipt['lanes'][lane] = {'linkedL0Objects': phase['linkedL0Objects'], 'linkedL0Modules': recorded_modules}
        flags = ['-parse-as-library', '-Onone', '-g', '-swift-version', '6', '-package-name', 'swift_CAD',
            '-whole-module-optimization', '-num-threads', '0', '-enable-testing', '-I', destination, '-I', modules]
        if lane == 'asan':
            flags += ['-sanitize=address']
        if lane in ('native', 'asan'):
            flags += ['-sdk', MACSDK, '-target', 'arm64-apple-macos27.0']
        else:
            flags += ['-target', 'wasm32-unknown-wasip1', '-sdk', SDKBASE / 'WASI.sdk',
                '-resource-dir', SDKBASE / ('swift.xctoolchain/usr/lib/swift' if lane == 'embedded' else 'swift.xctoolchain/usr/lib/swift_static'),
                '-static-stdlib', '-Xclang-linker', '-resource-dir', '-Xclang-linker',
                SDKBASE / 'swift.xctoolchain/usr/lib/swift_static/clang']
        if lane == 'embedded':
            flags += ['-enable-experimental-feature', 'Embedded']
        reused = None
        if args.reuse_production:
            previous_path = pathlib.Path(args.reuse_production).resolve() / 'receipt.json'
            previous = json.loads(previous_path.read_text())
            assert previous['compilerSHA256'] == receipt['compilerSHA256']
            assert all(previous['sourceHashes'][str(path.relative_to(ROOT))] == digest(path) for path in core + geometry)
            reused = previous['lanes'][lane]['compiledProducts']
            for path, expected in reused.items():
                artifact = pathlib.Path(path)
                assert digest(artifact) == expected, 'Focused production product mismatch'
                shutil.copyfile(artifact, destination / artifact.name)
            receipt['lanes'][lane]['reusedProductionReceiptSHA256'] = digest(previous_path)
            receipt['lanes'][lane]['reusedProductionCompilePhases'] = [phase for phase in previous['phases']
                if phase['name'] in (lane + '-CADCore', lane + '-CADGeometry')]
            print('Reused exact source/module/object production proof for ' + lane, flush=True)
        for module, sources in ([] if reused else [('CADCore', core), ('CADGeometry', geometry)]):
            command = [SWIFTC] + flags + ['-module-name', module, '-emit-module', '-emit-module-path',
                destination / (module + '.swiftmodule'), '-emit-object', '-o', destination / (module + '.code.o')]
            if module == 'CADGeometry':
                command += ['-Xfrontend', '-testable-import-module', '-Xfrontend', 'L0']
            command += sources
            run(lane + '-' + module, command, max(1, 1200 - (time.monotonic() - lane_started)))
        receipt['lanes'][lane]['compiledProducts'] = {str(path): digest(path) for path in destination.iterdir() if path.suffix in ('.o', '.swiftmodule')}
        executable = destination / ('ExecutionProof.wasm' if lane in ('wasm', 'embedded') else 'ExecutionProof')
        command = [SWIFTC] + flags + ['-DORIGINAL_QUERY_EXECUTION_ISOLATED_VERIFICATION'] + fixtures
        command += [destination / 'CADCore.code.o', destination / 'CADGeometry.code.o'] + objects + ['-o', executable]
        if lane == 'embedded':
            command += ['-Xlinker', SDKBASE / 'swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a',
                        '-Xlinker', '-lc++', '-Xlinker', '-lc++abi', '-Xlinker', '-lswift_Concurrency']
        run(lane + '-link', command, max(1, 1200 - (time.monotonic() - lane_started)))
        receipt['lanes'][lane]['artifactSHA256'] = digest(executable)
        runtime = ['/usr/local/bin/node', ROOT / 'Tests/OriginalPublicAcceptanceVerification/RunWASI.mjs', executable] if lane in ('wasm', 'embedded') else [executable]
        run(lane + '-runtime', runtime, 120)
    save()
    print('PASS focused original execution all requested lanes', flush=True)


if __name__ == '__main__':
    main()
