#!/usr/bin/env python3
"""Compile actual Native consumers against generation-bound lower and DTO products."""
import argparse
import hashlib
import yaml
import json
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native','asan','wasm','embedded'])
parser.add_argument('--output', type=Path)
args = parser.parse_args()
portable = args.lane in {'wasm','embedded'}
root = Path(__file__).resolve().parents[2]
evidence = root / 'Tests/OriginalNativeConsumerIntakeVerification/Evidence'
lower_receipt = evidence / (args.lane+'-query-field-accepted/generation.json')
production_directory = root / 'Tests/OriginalDomainConsumerVerification/Evidence/M6'
production_receipt = production_directory / (args.lane+'/receipt.json' if portable else 'receipt.json')
lower = json.loads(lower_receipt.read_text())
production = json.loads(production_receipt.read_text())
cache_root = Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-'+(args.lane if portable else 'native')+'-production')
cache = cache_root / ('wasm32-unknown-wasip1/debug' if portable else 'out/Products/Debug')
work = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='cad-current-m6-consumers-'+args.lane+'-'))
if args.output:
    work.mkdir(parents=True,exist_ok=False)
print('OUTPUT', work, flush=True)
records = []

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def execute(label, command, timeout=120):
    start = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    (work / (label + '.log')).write_text(result.stdout + result.stderr)
    records.append(dict(label=label, command=command, timeoutSeconds=timeout,
                        elapsedSeconds=time.monotonic()-start, exitCode=result.returncode))
    (work / 'runs.json').write_text(json.dumps(records, indent=2)+'\n')
    print(label, result.returncode, round(records[-1]['elapsedSeconds'], 3), flush=True)
    if result.returncode:
        print(result.stderr[-7000:])
        raise SystemExit(result.returncode)


premises = {}
for name, expected in lower['inputs'].items():
    path = Path(name)
    if path.is_relative_to(root) and not path.is_relative_to(root / '.build'):
        if digest(path) != expected:
            raise RuntimeError('Changed lower generation input: ' + name)
        premises[name] = expected
for name, expected in lower['artifacts'].items():
    if digest(Path(name)) != expected:
        raise RuntimeError('Changed lower generation artifact: ' + name)
for name, expected in lower['logs'].items():
    if digest(Path(name)) != expected:
        raise RuntimeError('Changed lower generation log: ' + name)
# The cached Geometry's old solver/DI code is never selected by the typed assembly.
# Core and literal Native DTO/validation inputs are unchanged; separate lower
# modules provide every new identity and equality operation.
for name, expected in production['source_sha256'].items():
    if name.startswith(('Sources/CADCore/', 'Sources/CADTopology/', 'Sources/CADGeometry/PeriodicBSpline/')) or name in {
        'Sources/CADGeometry/BSplineCurve3D.swift', 'Sources/CADGeometry/BSplineSurface3D.swift',
        'Sources/CADGeometry/SurfaceParameterCurve.swift', 'Sources/CADGeometry/Surface3D.swift',
        'Sources/CADGeometry/ScalarInterval.swift', 'Sources/CADGeometry/SurfaceParameterBox.swift',
        'Sources/CADGeometry/RationalBivariateAlgebra/RationalAlgebraGeometryFailure.swift',
        'Sources/CADGeometry/CurveParameterDomain.swift', 'Sources/CADGeometry/SurfaceParameterDomain.swift'
    }:
        path = root / name
        if digest(path) != expected:
            raise RuntimeError('Changed cached Native DTO premise: ' + name)
        premises[str(path)] = expected
cached = {}
modules = ['CADCore','CADGeometry','CADTopology','CADKernel','HashTreeCollections','InternalCollectionsUtilities']
cache_objects = []
for name, expected in production['products'].items():
    path = cache_root / name
    required = (path.suffix == '.swiftmodule' and path.stem in modules) or (
        path.suffix == '.o' and (path.stem in modules or path.parent.name in {n+'.build' for n in modules}))
    if required:
        if digest(path) != expected:
            raise RuntimeError('Changed cached product: ' + name)
        cached[str(path)] = expected
        if path.suffix == '.o': cache_objects.append(path)
for module_name in modules:
    if not any(Path(n).name == module_name+'.swiftmodule' for n in cached):
        raise RuntimeError('Missing cached module: '+module_name)
for product, expected in production['artifact_sha256'].items():
    path = cache / (product+".wasm" if portable else product)
    if digest(path) != expected:
        raise RuntimeError('Changed accepted production executable: ' + product)
    cached[str(path)] = expected
for name, expected in production['runtime_log_sha256'].items():
    path = production_receipt.parent / name
    if digest(path) != expected:
        raise RuntimeError('Changed accepted production runtime log: ' + name)
    cached[str(path)] = expected

product = Path(next(name for name in lower['artifacts'] if name.endswith('/NativeConsumerProof'+('.wasm' if portable else ''))))
lower_products = product.parent
swift = Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc')
plan_path = next(Path(n) for n in lower['artifacts'] if n.endswith('/debug.yaml'))
plan = yaml.load(plan_path.read_text(),Loader=yaml.CSafeLoader)['commands']
source_command = next(v['args'] for v in plan.values() if 'SourceIssuer' in v.get('args',[]) and '-emit-module' in v['args'])
common = [str(swift),'-swift-version','6','-package-name','nativeexactrelationverification',
          '-I',str(cache/'Modules' if portable else cache),'-I',str(lower_products/'Modules'),'-I',str(work)]
for option in ['-sdk','-target','-resource-dir','-tools-directory']:
    if option in source_command:
        common += [option,source_command[source_command.index(option)+1]]
if portable:
    common += ['-static-stdlib']
else:
    common += ['-target','arm64-apple-macos15.0']
link_command = next(v['args'] for v in plan.values() if v.get('args') and '-emit-executable' in v['args'])
link_flags = []
for index, option in enumerate(link_command):
    if portable and option in {'-Xclang-linker','-Xlinker'}: link_flags += [option,link_command[index+1]]
if args.lane == 'embedded': common += ['-enable-experimental-feature','Embedded','-whole-module-optimization','-Onone']
if args.lane == 'asan': common += ['-sanitize=address','-O']
inputs = {}
(work/'driver.py').write_bytes(Path(__file__).read_bytes())
if args.lane == 'embedded':
    resource = Path(source_command[source_command.index('-resource-dir')+1])
    unicode_library = resource/'embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a'
    if not unicode_library.is_file(): raise RuntimeError('Missing matching Embedded Unicode table library')
    inputs[str(unicode_library)] = digest(unicode_library)
    link_flags += ['-Xlinker',str(unicode_library)]

def module(name, paths, definitions):
    for path in paths:
        inputs[str(path)] = digest(path)
    (work/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
    execute(name, common+['-parse-as-library','-enable-testing','-emit-module','-emit-library','-static',
        '-module-name',name,*sum((['-D',d] for d in definitions),[]),*map(str,paths),
        '-emit-module-path',str(work/(name+'.swiftmodule')),'-o',str(work/('lib'+name+'.a'))])

source = root / 'Sources/CADGeometry/OriginalSourceIssuance'
module('SourceGeometryAdapters',[source/n for n in ['BSplineCurve3D+OriginalSourceReading.swift',
    'BSplineSurface3D+OriginalSourceReading.swift','OriginalBSplineCurveSnapshotProvider.swift',
    'OriginalBSplineSurfaceSnapshotProvider.swift']],['ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION'])
consumers = sorted(path for path in (root/'Sources/CADGeometry/NativeExactRelations').glob('*.swift')
                   if 'Original' not in path.name)
consumers += [root/'Sources/CADGeometry'/name for name in [
    'NativeExactGeometricRelations/NativeExactGeometryPublicationFailure.swift',
    'NativeExactGeometricRelations/NativeExactGeometricRelationFailure.swift',
    'RationalBivariateAlgebra/GeometryExactScalarFailure.swift',
    'RationalBivariateAlgebra/ExactGeometricRelation/ExactGeometricRelationFailure.swift']]
consumers += sorted((root/'Sources/CADGeometry/OriginalBoundaryClipping').glob('*Exact*.swift'))
consumers += sorted((root/'Sources/CADGeometry/OriginalSurfaceEmbedding').glob('*Exact*.swift'))
module('NativeDomainAdapters',consumers,['NATIVE_DOMAIN_ISOLATED_VERIFICATION',
    'NATIVE_FAMILY_ISOLATED_VERIFICATION','SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION','L6_ISOLATED_VERIFICATION'])
fixtures = root / 'Tests/OriginalDomainConsumerVerification/Sources'
module('NativeExactSelfFixtures', sorted((fixtures/'M6SelfFixtures').glob('*.swift')),['NATIVE_DOMAIN_ISOLATED_VERIFICATION'])
objects = [Path(name) for name in lower['artifacts'] if name.endswith('.o') and Path(name).parent.name in {
    n+'.build' for n in ['L0','L1','L2','L3','L4','L5','DI0','DI','SourceIssuer']}]
proof = fixtures/'M6SelfProof/Proof.swift'
inputs[str(proof)] = digest(proof)
(work/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
executable = work/('SelfProof.wasm' if portable else 'SelfProof')
execute('link-self',common+link_flags+['-parse-as-library',str(proof),str(work/'libNativeExactSelfFixtures.a'),
    str(work/'libNativeDomainAdapters.a'),str(work/'libSourceGeometryAdapters.a'),*map(str,objects),
    *map(str,[p for p in cache_objects if not (p.stem in {'CADTopology','CADKernel'} or p.parent.name in {'CADTopology.build','CADKernel.build'})]),
    '-o',str(executable)])
def runtime(product, group):
    if not portable: return [str(product),group]
    return ['/usr/local/bin/node',str(root/'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'),str(product),group]
for group in ['diagonal','folded','seam','pole']:
    execute('self-'+group,runtime(executable,group))
module('NativeKernelAdapters',sorted((root/'Sources/CADKernel/OriginalBoundaryClipping').glob('*Exact*.swift')),['NATIVE_DOMAIN_ISOLATED_VERIFICATION'])
module('NativeExactBoundaryFixtures',sorted((fixtures/'M6BoundaryFixtures').glob('*.swift')),['NATIVE_DOMAIN_ISOLATED_VERIFICATION'])
proof = fixtures/'M6BoundaryProof/Proof.swift'
inputs[str(proof)] = digest(proof)
(work/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
boundary = work/('BoundaryProof.wasm' if portable else 'BoundaryProof')
execute('link-boundary',common+link_flags+['-parse-as-library',str(proof),str(work/'libNativeExactBoundaryFixtures.a'),
    str(work/'libNativeKernelAdapters.a'),str(work/'libNativeDomainAdapters.a'),str(work/'libSourceGeometryAdapters.a'),
    *map(str,objects),*map(str,cache_objects),
    '-o',str(boundary)])
for group in ['holes','nonconvex','sides','seamPole','failures']:
    execute('boundary-'+group,runtime(boundary,group))
for name, expected in {**premises, **cached, **inputs, **lower['artifacts']}.items():
    if digest(Path(name)) != expected:
        raise RuntimeError('Changed admitted premise during verification: '+name)
(work/'receipt.json').write_text(json.dumps(dict(inputs=inputs,premises=premises,cached=cached,
    lowerGenerationReceiptSHA256=digest(lower_receipt),productionReceiptSHA256=digest(production_receipt),
    driverSHA256=digest(__file__),lane=args.lane,artifacts={str(p):digest(p) for p in work.iterdir() if p.suffix in {'.swiftmodule','.a'}},
    runs=records,products={str(p):digest(p) for p in [executable,boundary]},logs={p.name:digest(p) for p in work.glob('*.log')},
    scope='Actual current Native source/DI/L5/self consumer; unchanged receipt-bound Native DTO validation only. Actual public Kernel boundary fixtures and unchanged receipt-bound Topology validator; no broad CAD or lower rebuild. General families remain separate.'),indent=2)+'\n')
