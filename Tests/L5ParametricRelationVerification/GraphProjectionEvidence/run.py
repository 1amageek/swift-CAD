#!/usr/bin/env python3
"""Run one bounded B0-B2 verification lane and bind its compiled inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('component', choices=['source', 'relation'])
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
swift = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift'
node = '/usr/local/bin/node'
package = 'OriginalSourceIssuanceVerification' if args.component == 'source' else 'L5ParametricRelationVerification'
product = 'SourceIssuerProof' if args.component == 'source' else 'L5Proof'
cache = root / '.build' / f'pg-{ "source" if args.component == "source" else "l5" }-{args.lane}'
out = Path(__file__).resolve().parent / f'{args.component}-{args.lane}'
out.mkdir(exist_ok=True)
records = []

def execute(label, command, seconds):
    start = time.monotonic()
    with (out / f'{label}.log').open('w') as log:
        process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
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
    common += ['--sanitize', 'address']
portable = args.lane in ['wasm', 'embedded']
if portable:
    common += ['--swift-sdk', 'swift-6.4.0-RELEASE_wasm'+('-embedded' if args.lane == 'embedded' else '')]
    if args.lane == 'embedded':
        common += ['-Xswiftc', '-whole-module-optimization', '-Xswiftc', '-Onone']
execute('build', [swift, 'build']+common+(['--product', product] if portable else ['--build-tests']), 180)
if args.lane == 'asan' and args.component == 'relation':
    artifact = cache / 'arm64-apple-macosx' / 'debug' / product
    for group in ['projection']+[str(i) for i in range(9)]+['failures','legacy']:
        execute(f'proof-{group}', [str(artifact),group], 60)
elif portable:
    execute('node', [node, '--version'], 10)
    artifact = cache / 'wasm32-unknown-wasip1' / 'debug' / f'{product}.wasm'
    if args.component == 'source':
        execute('proof', [node, 'Tests/L3RealCellVerification/ConvergenceEvidence/retained-run_wasi_smoke.mjs', str(artifact)], 120)
    else:
        for group in ['projection']+[str(i) for i in range(9)]+['failures','legacy']:
            execute(f'proof-{group}', [node, 'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs', str(artifact), group], 120)
elif args.component == 'relation':
    execute('tests-graphs', [swift, 'test']+common+['--skip-build', '--filter', 'guardedGraphRelations'], 120)
    execute('tests-other', [swift, 'test']+common+['--skip-build', '--skip', 'guardedGraphRelations'], 120)
    artifact = cache / 'arm64-apple-macosx' / 'debug' / product
else:
    execute('tests', [swift, 'test']+common+['--skip-build'], 120)
    artifact = cache / 'arm64-apple-macosx' / 'debug' / product

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
