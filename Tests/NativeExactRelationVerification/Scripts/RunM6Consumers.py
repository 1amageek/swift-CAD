"""Bounded actual Native L5 boundary/self component verification, with immutable input binding."""
import argparse
import hashlib
import json
import os
import signal
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--build-path',type=Path,required=True)
parser.add_argument('--collections',type=Path,required=True)
parser.add_argument('--evidence',type=Path,required=True)
parser.add_argument('--lane',choices=['native','wasm','embedded'],default='native')
parser.add_argument('--jobs',type=int,choices=[1,2,4],default=4,help='Owned compiler concurrency; correctness budgets are unchanged')
parser.add_argument('--build-seconds',type=int,choices=[120,300,1200],default=300,help='Bounded production compilation; runtime remains 120 seconds')
parser.add_argument('--component',choices=['both','boundary','self'],default='both',help='Explicit component proof scope; selected fixtures remain unchanged')
parser.add_argument('--target',help='Diagnostic component compile only; does not establish runtime completion')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
build = args.build_path.resolve()
evidence = args.evidence.resolve()
evidence.mkdir(parents=True,exist_ok=True)
swift = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift')
env = dict(os.environ,CAD_COLLECTIONS_PATH=str(args.collections.resolve()))
sdk = None if args.lane == 'native' else 'swift-6.4.0-RELEASE_wasm' + ('-embedded' if args.lane == 'embedded' else '')
unicode_library = Path.home()/'.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def snapshot():
    paths = [root/'Tests/NativeExactRelationVerification/Package.swift',Path(__file__).resolve()]
    for directory in ['Sources/CADCore','Sources/CADGeometry','Sources/CADTopology','Sources/CADKernel/OriginalBoundaryClipping',
                      'Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryFixtures','Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryProof',
                      'Tests/OriginalDomainConsumerVerification/Sources/M6SelfFixtures','Tests/OriginalDomainConsumerVerification/Sources/M6SelfProof']:
        paths += sorted((root/directory).rglob('*.swift'))
    return {str(path.relative_to(root)):digest(path) for path in paths}

before = snapshot()
attempts_path = evidence/'attempts.json'
attempts = json.loads(attempts_path.read_text()) if attempts_path.is_file() else []

def run(command,filename,timeout_seconds=120):
    started = time.monotonic()
    destination = evidence/filename
    if destination.is_file():
        ordinal = 1
        archive = destination.with_name(destination.stem+'-previous-'+str(ordinal)+destination.suffix)
        while archive.exists():
            ordinal += 1
            archive = destination.with_name(destination.stem+'-previous-'+str(ordinal)+destination.suffix)
        destination.rename(archive)
    with destination.open('w') as log:
        process = subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            status = process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            # SwiftPM's native backend may give frontend workers their own groups.
            # Match only this invocation's unique scratch path before stopping them.
            for line in subprocess.check_output(['ps','-axo','pid,comm,args'],text=True,timeout=10).splitlines():
                fields = line.strip().split(None,2)
                if len(fields) == 3 and fields[1].rsplit('/',1)[-1] in ['swift-frontend','swiftc','swift-build'] and str(build) in fields[2]:
                    try:os.kill(int(fields[0]),signal.SIGKILL)
                    except ProcessLookupError:pass
            os.killpg(process.pid,signal.SIGKILL)
            process.wait()
            attempts.append({'command':command,'elapsed_seconds':time.monotonic()-started,'exit_code':None,'timeout_seconds':timeout_seconds})
            attempts_path.write_text(json.dumps(attempts,indent=2)+'\n')
            raise RuntimeError(str(timeout_seconds)+'-second timeout; stopped owned process group and retained partial objects')
    attempts.append({'command':command,'elapsed_seconds':time.monotonic()-started,'exit_code':status,'timeout_seconds':timeout_seconds})
    attempts_path.write_text(json.dumps(attempts,indent=2)+'\n')
    if status:
        raise RuntimeError('Failed command; inspect '+str(evidence/filename))

def compile_target(kind,name,filename):
    command = [str(swift),'build','--package-path',str(root/'Tests/NativeExactRelationVerification'),
               '--scratch-path',str(build),'-j',str(args.jobs),'-Xswiftc','-j'+str(args.jobs),kind,name]
    if sdk:
        command += ['--build-system','native','--swift-sdk',sdk,'--disable-index-store','-Xswiftc','-Onone','-Xswiftc','-gnone']
    if args.lane == 'embedded':
        if not unicode_library.is_file():raise RuntimeError('Matching Embedded Unicode table library is missing')
        command += ['-Xswiftc','-whole-module-optimization','-Xlinker',str(unicode_library)]
    run(command,filename,args.build_seconds)

if args.target:
    compile_target('--target',args.target,'diagnostic-build.log')
    print('PASS diagnostic component compile; runtime acceptance remains pending')
    raise SystemExit(0)

products = ['NativeExactBoundaryProof','NativeExactSelfProof'] if args.component == 'both' else ['NativeExactBoundaryProof' if args.component == 'boundary' else 'NativeExactSelfProof']
for product in products:
    compile_target('--product',product,product+'-build.log')
if snapshot() != before:
    raise RuntimeError('Source changed during compilation; no completion receipt can be published')
artifacts = {}
runtime_logs = {}
for product in reversed(products):
    artifact = build/('wasm32-unknown-wasip1/debug/'+product+'.wasm') if sdk else build/'out/Products/Debug'/product
    if not artifact.is_file() and not sdk:artifact = build/'debug'/product
    if product == 'NativeExactBoundaryProof':
        for group in ['holes','nonconvex','sides','seamPole','failures']:
            filename = product+'-'+group+'-runtime.log'
            command = ['node',str(root/'Tests/NativeExactRelationVerification/Scripts/RunGeometricProof.mjs'),str(artifact),group] if sdk else [str(artifact),group]
            run(command,filename)
            if ('PASS M6 exact L5 public face boundary consumers '+group) not in (evidence/filename).read_text():
                raise RuntimeError('Missing terminal completion marker for '+group)
            runtime_logs[filename] = digest(evidence/filename)
    else:
        for group in ['diagonal','folded','seam','pole'] if sdk else ['all']:
            filename = product+'-'+group+'-runtime.log' if sdk else product+'-runtime.log'
            command = ['node',str(root/'Tests/NativeExactRelationVerification/Scripts/RunGeometricProof.mjs'),str(artifact),group] if sdk else [str(artifact)]
            run(command,filename)
            if 'PASS M6 complete Native exact self-contact consumer' not in (evidence/filename).read_text():
                raise RuntimeError('Missing terminal completion marker for '+product)
            runtime_logs[filename] = digest(evidence/filename)
    artifacts[product] = digest(artifact)
if snapshot() != before:
    raise RuntimeError('Source changed during runtime; no completion receipt can be published')
inputs = {}
for listing in list(build.rglob('*.SwiftFileList'))+list(build.rglob('sources')):
    for value in listing.read_text().splitlines():
        path = Path(value.strip().strip('"')).resolve()
        if path.is_file():
            inputs[str(path)] = digest(path)
modules = {}
for path in build.rglob('*'):
    if path.is_file() and path.suffix in ['.o','.swiftmodule','.a']:
        modules[str(path.relative_to(build))] = digest(path)
receipt = {'scope':('Actual production CADCore/CADGeometry self-contact component; no Topology/Kernel acceptance.' if args.component == 'self' else 'Actual production CADCore/CADGeometry/CADTopology and CADKernel OriginalBoundaryClipping component; not full CADKernel/Modeling or unrelated CAD target acceptance.'),'component':args.component,
           'lane':args.lane,'swift_sdk':sdk,
           'source_sha256':before,'compiler_inputs':inputs,'products':modules,'artifact_sha256':artifacts,
           'commands':attempts,'runtime_log_sha256':runtime_logs,
           'compiler':subprocess.check_output([str(swift),'--version'],text=True,timeout=10).strip(),
           'target_info':json.loads(subprocess.check_output([str(swift),'-print-target-info'],text=True,timeout=10)),
           'native_sdk':{'path':subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True,timeout=10).strip(),
                         'version':subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-version'],text=True,timeout=10).strip(),
                         'build':subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-build-version'],text=True,timeout=10).strip()}}
(evidence/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
if sdk:
    receipt['node_version'] = subprocess.check_output(['node','--version'],text=True,timeout=10).strip()
    receipt['target_triple'] = 'wasm32-unknown-wasip1'
    if args.lane == 'embedded':receipt['unicode_data_tables'] = {'path':str(unicode_library),'sha256':digest(unicode_library)}
    (evidence/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS M6 exact Native boundary/self source snapshot, component compile and public runtime')
