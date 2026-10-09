"""Build and run the actual Native finite-family consumer with checked source snapshots."""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--build-path', type=Path, required=True)
parser.add_argument('--collections', type=Path, required=True)
parser.add_argument('--evidence', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
build = args.build_path.resolve()
evidence = args.evidence.resolve()
evidence.mkdir(parents=True, exist_ok=True)
swift = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def snapshot():
    paths = [root/'Tests/NativeExactRelationVerification/Package.swift']
    for directory in ['Sources/CADCore','Sources/CADGeometry','Tests/OriginalDomainConsumerVerification/Sources/FamilyFixtures',
                      'Tests/OriginalDomainConsumerVerification/Sources/FamilyProof','Tests/OriginalDomainConsumerVerification/Sources/M3Fixtures','Tests/OriginalDomainConsumerVerification/Sources/M3Proof']:
        paths += sorted((root/directory).rglob('*.swift'))
    return {str(path.relative_to(root)):digest(path) for path in paths}

before = snapshot()
env = dict(os.environ, CAD_COLLECTIONS_PATH=str(args.collections.resolve()))
attempts_path = evidence/'attempts.json'
commands = json.loads(attempts_path.read_text()) if attempts_path.is_file() else []

def run(command, filename):
    started = time.monotonic()
    with (evidence/filename).open('w') as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            commands.append({'command':command,'elapsed_seconds':time.monotonic()-started,'exit_code':None,'timeout_seconds':120})
            attempts_path.write_text(json.dumps(commands,indent=2)+'\n')
            raise RuntimeError('Timed out at 120 seconds; compiler group stopped and partial build remains in the owned scratch directory')
    commands.append({'command':command,'elapsed_seconds':time.monotonic()-started,'exit_code':status})
    attempts_path.write_text(json.dumps(commands,indent=2)+'\n')
    if status:
        raise RuntimeError('Failed command; inspect '+str(evidence/filename))

run([str(swift),'build','--package-path',str(root/'Tests/NativeExactRelationVerification'),
     '--scratch-path',str(build),'-j','4','-Xswiftc','-j4','--product','NativeDomainFamilyProof'],'build.log')
run([str(swift),'build','--package-path',str(root/'Tests/NativeExactRelationVerification'),
     '--scratch-path',str(build),'-j','4','-Xswiftc','-j4','--product','NativePrimitiveSourceProof'],'m3-build.log')
if snapshot() != before:
    raise RuntimeError('Source changed while compiling; this snapshot cannot establish completion')
artifact = build/'out/Products/Debug/NativeDomainFamilyProof'
if not artifact.is_file():
    artifact = build/'debug/NativeDomainFamilyProof'
run([str(artifact)],'runtime.log')
m3_artifact = artifact.with_name('NativePrimitiveSourceProof')
run([str(m3_artifact)],'m3-runtime.log')
if snapshot() != before:
    raise RuntimeError('Source changed while executing; this snapshot cannot establish completion')
log = (evidence/'runtime.log').read_text()
if 'PASS M2 complete Native domain family consumers' not in log:
    raise RuntimeError('Missing terminal runtime completion marker')
if 'PASS M3 actual primitive sources, stored-N UV, original physical wrappers' not in (evidence/'m3-runtime.log').read_text():
    raise RuntimeError('Missing M3 terminal runtime completion marker')
inputs = {}
for listing in (build/'out/Intermediates.noindex').rglob('*.SwiftFileList'):
    for value in listing.read_text().splitlines():
        path = Path(value.strip().strip('"')).resolve()
        if path.is_file():
            inputs[str(path)] = digest(path)
products = {}
for path in (build/'out/Products/Debug').rglob('*'):
    if path.is_file() and (path.suffix in ['.o','.swiftmodule','.a'] or path == artifact):
        products[str(path.relative_to(build))] = digest(path)
receipt = {'scope':'Actual production CADCore/CADGeometry Native finite-family parameter consumer; no other CAD target.',
           'source_sha256':before,'compiler_inputs':inputs,'products':products,'artifact_sha256':digest(artifact),'m3_artifact_sha256':digest(m3_artifact),
           'commands':commands,'runtime_log_sha256':digest(evidence/'runtime.log'),
           'm3_runtime_log_sha256':digest(evidence/'m3-runtime.log'),'runner_sha256':digest(Path(__file__).resolve()),
           'compiler':subprocess.check_output([str(swift),'--version'],text=True).strip()}
(evidence/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS M2 Native source snapshot, full production compile and runtime')
