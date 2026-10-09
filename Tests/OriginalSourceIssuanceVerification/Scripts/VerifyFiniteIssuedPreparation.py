#!/usr/bin/env python3
"""Execute finite issuer and consumer proofs using explicit checked lower products."""
from pathlib import Path
import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--lane', choices=['native', 'asan', 'wasm', 'embedded'], required=True)
parser.add_argument('--lower-products', type=Path)
parser.add_argument('--reuse-source', action='store_true', help='Reuse unchanged, previously verified issuer products')
args = parser.parse_args()
lane = args.lane
root = Path(__file__).resolve().parents[3]
scripts = root / 'Tests/OriginalSourceIssuanceVerification/Scripts'
logs = root / '.build/handoff-evidence'
logs.mkdir(parents=True, exist_ok=True)
swift = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift'
wasm = lane in ('wasm', 'embedded')
command = [swift, 'build' if wasm else 'test', '--package-path', str(root / 'Tests/OriginalSourceIssuanceVerification'),
           '--build-path', str(root / ('.build/handoff-' + lane)), '--jobs', '2']
if lane == 'asan': command += ['--sanitize', 'address']
if wasm:
    command += ['--swift-sdk', 'swift-6.4.0-RELEASE_wasm' + ('-embedded' if lane == 'embedded' else ''), '--product', 'SourceIssuerProof']
if not args.reuse_source:
    subprocess.run(['python3', str(scripts / 'Guard.py'), '--timeout', '120', '--log', str(logs / ('finite-' + lane + '-source.log')), '--', *command], check=True, timeout=130)
if wasm and not args.reuse_source:
    artifact = root / ('.build/handoff-' + lane) / 'out/Products/Debug-webassembly-wasm32/SourceIssuerProof.wasm'
    subprocess.run(['python3', str(scripts / 'Guard.py'), '--timeout', '120', '--log', str(logs / ('finite-' + lane + '-runtime.log')), '--',
                    '/usr/local/bin/node', str(scripts / 'RunWASI.mjs'), str(artifact)], check=True, timeout=130)
for name, stage in [('VerifyCoordinateTransfer.py', 'coordinate'), ('VerifyIssuedDomainBinding.py', 'domain'), ('VerifyIssuedMaps.py', 'map')]:
    command = ['python3', str(scripts / name), '--lane', lane]
    if args.lower_products:
        command += ['--lower-products', str(args.lower_products.resolve())]
    subprocess.run(['python3', str(scripts / 'Guard.py'), '--timeout', '120',
        '--log', str(logs / ('finite-' + lane + '-' + stage + '.log')), '--', *command], check=True, timeout=130)
print('FINITE_ISSUED_PREPARATION_OK', lane)
