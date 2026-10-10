#!/usr/bin/env python3
"""Run one bounded issued graph/L6 verification lane and bind its compiled inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
args = parser.parse_args()
args.component = 'relation'
root = Path(__file__).resolve().parents[3]
swift = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift'
node = '/usr/local/bin/node'
package = 'OriginalGraphRelationVerification'
product = 'GeneralGraphProof'
cache = root / '.build' / f'pg-b3-{args.lane}'
out = Path(__file__).resolve().parent / f'general-{args.lane}'
out.mkdir(exist_ok=True)
records = []

def execute(label, command, seconds):
    start = time.monotonic()
    with (out / f'{label}.log').open('w') as log:
        process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            # SwiftPM may detach compiler process groups; retain this invocation's tree.
            tree = {}
            for line in subprocess.check_output(['ps', '-axo', 'pid=,ppid='], text=True).splitlines():
                child, parent = map(int, line.split()); tree.setdefault(parent, []).append(child)
            descendants = []
            pending = [process.pid]
            while pending:
                children = tree.get(pending.pop(), []); descendants.extend(children); pending.extend(children)
            for child in reversed(descendants):
                try: os.kill(child, signal.SIGTERM)
                except ProcessLookupError: pass
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            for child in descendants:
                try: os.kill(child, signal.SIGKILL)
                except ProcessLookupError: pass
            code = 124
    record = dict(label=label, command=command, timeoutSeconds=seconds, elapsedSeconds=round(time.monotonic()-start, 3), exitCode=code)
    records.append(record)
    print(json.dumps(record), flush=True)
    if code:
        (out / 'result.json').write_text(json.dumps(dict(success=False, runs=records), indent=2)+'\n')
        raise SystemExit(code)

execute('toolchain', [swift, '--version'], 10)
execute('sdk', [swift, 'sdk', 'list'], 10)
common = ['--build-system', 'native', '--package-path', f'Tests/{package}', '--build-path', str(cache), '-j', '2']
if args.lane == 'asan':
    common += ['--sanitize', 'address', '-Xswiftc', '-O']
portable = args.lane in ['wasm', 'embedded']
if portable:
    common += ['--swift-sdk', 'swift-6.4.0-RELEASE_wasm'+('-embedded' if args.lane == 'embedded' else '')]
    if args.lane == 'embedded':
        common += ['-Xswiftc', '-whole-module-optimization', '-Xswiftc', '-Onone']
execute('build', [swift, 'build']+common+['--product', product],120)
artifact=cache / ('wasm32-unknown-wasip1' if portable else 'arm64-apple-macosx') / 'debug' / (product+'.wasm' if portable else product)
execute('proof',[node,'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs',str(artifact),'general'] if portable else [str(artifact)],120)

inputs = {}
for source_list in cache.rglob('*.build/sources'):
    for line in source_list.read_text().splitlines():
        path = Path(line).resolve()
        if path.is_file() and path.is_relative_to(root) and not path.is_relative_to(root / '.build'):
            inputs[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
for relative in [f'Tests/{package}/Package.swift']:
    inputs[relative] = hashlib.sha256((root / relative).read_bytes()).hexdigest()
(out / 'inputs.json').write_text(json.dumps(dict(sorted(inputs.items())), indent=2)+'\n')
artifacts = {str(artifact.relative_to(root)): hashlib.sha256(artifact.read_bytes()).hexdigest()}
for path in cache.rglob('*PackageTests'):
    if path.is_file() and path.stat().st_mode & 0o111:
        artifacts[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
(out / 'result.json').write_text(json.dumps(dict(success=True, runs=records, artifacts=artifacts, compiledInputCount=len(inputs), verificationDriverSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()), indent=2)+'\n')
print(f'PASS {args.component} {args.lane}: {len(inputs)} bound inputs', flush=True)
