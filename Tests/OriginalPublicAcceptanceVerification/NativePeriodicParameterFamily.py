#!/usr/bin/env python3
"""Verify the public symbolic Native family using receipt-admitted unchanged lower/DTO products."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native', 'asan', 'wasm', 'embedded'])
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--reuse-module', type=Path)
parser.add_argument('--proof', choices=['acceptance','binding'], default='acceptance')
parser.add_argument('--compile-timeout', type=int, default=120)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.output.resolve()
work.mkdir(parents=True, exist_ok=False)
original = root / 'Tests/OriginalNativeConsumerIntakeVerification/Consumers.py'
source = original.read_text()
source = source.replace('root = Path(__file__).resolve().parents[2]', 'root = Path(' + repr(str(root)) + ')')
unselected = [
    'Tests/OriginalGraphRelationVerification/Package.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalFiniteBSplineChartPreparer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalOffsetLawIssuer.swift',
    'Sources/CADGeometry/OriginalSourceIssuance/DefaultOriginalSpatialChartIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/DefaultOriginalParameterIdentityIssuer.swift',
    'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity/OriginalParameterIdentity.swift']
needle = "    path = Path(name)\n    if path.is_relative_to(root) and not path.is_relative_to(root / '.build'):"
assert source.count(needle) == 1
source = source.replace(needle, "    path = Path(name)\n    if name in " + repr({str(root / p) for p in unselected}) + ":\n        continue\n    if path.is_relative_to(root) and not path.is_relative_to(root / '.build'):")
for component in ['OriginalBoundaryClipping','OriginalSurfaceEmbedding']:
    needle = "consumers += sorted((root/'Sources/CADGeometry/" + component + "').glob('*Exact*.swift'))"
    assert source.count(needle) == 1
    source = source.replace(needle, '')
start = source.index("fixtures = root / 'Tests/OriginalDomainConsumerVerification/Sources'")
end = source.index("for name, expected in {**premises", start)
source = source[:start] + r'''fixtures = root / 'Tests/OriginalDomainConsumerVerification/Sources/FamilyFixtures'
objects = [Path(name) for name in lower['artifacts'] if name.endswith('.o') and Path(name).parent.name in {
    n+'.build' for n in ['L0','L1','L2','L3','L4','L5','DI0','DI','SourceIssuer']}]
proof = root/'Tests/OriginalPublicAcceptanceVerification/NativePeriodicParameterFamily.swift'
compiled_fixtures = []
for path in sorted(fixtures.glob('*.swift')):
    inputs[str(path)] = digest(path)
    generated = work/path.name
    body = path.read_text()
    body = body.replace('@testable import CADGeometry', '@testable import NativeDomainAdapters')
    body = body.replace('import CADGeometry', '\n'.join('import struct CADGeometry.'+n for n in ['BSplineCurve3D','BSplineSurface3D','DefaultCurveSurfaceIntersector','DefaultSurfaceSurfaceIntersector']))
    generated.write_text('import L0\nimport L1\nimport L2\nimport L3\nimport L4\nimport L5\nimport DI0\nimport DI\nimport SourceIssuer\nimport NativeDomainAdapters\nimport SourceGeometryAdapters\n'+body)
    inputs[str(generated)] = digest(generated)
    compiled_fixtures.append(generated)
inputs[str(proof)] = digest(proof)
inputs[str(swift.resolve())] = digest(swift.resolve())
inputs[str(swift.parent/'swift-frontend')] = digest(swift.parent/'swift-frontend')
(work/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
executable = work/('FamilyProof.wasm' if portable else 'FamilyProof')
execute('link-family',common+link_flags+['-parse-as-library',str(proof),*map(str,compiled_fixtures),
    str(work/'libNativeDomainAdapters.a'),str(work/'libSourceGeometryAdapters.a'),*map(str,objects),
    *map(str,[p for p in cache_objects if not (p.stem in {'CADTopology','CADKernel'} or p.parent.name in {'CADTopology.build','CADKernel.build'})]),
    '-o',str(executable)])
runtime = ['/usr/local/bin/node',str(root/'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'),str(executable),'all'] if portable else [str(executable)]
execute('runtime-family',runtime)
''' + source[end:]
source = source.replace("[executable,boundary]", "[executable]")
source = source.replace('Actual current Native source/DI/L5/self consumer; unchanged receipt-bound Native DTO validation only. Actual public Kernel boundary fixtures and unchanged receipt-bound Topology validator; no broad CAD or lower rebuild. General families remain separate.', 'Actual public symbolic Native CS parameter family, original source/domain/L5 receipts and changed finite-family regression; unchanged admitted lower/DTO products only. Ordinary XYZ, boundary/self and general families remain separate; no broad CAD/L2-L6 rebuild.')
source = source.replace("'-swift-version','6','-package-name'", "'-j2','-swift-version','6','-package-name'")
# Bound and reap the entire owned compiler/runtime process group on timeout.
needle = '    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)'
replacement = "    timeout = " + str(args.compile_timeout) + " if label != 'runtime-family' else timeout\n" + r"""    import os, signal, resource
    cpu_limit = 360 if label == 'runtime-family' else 240
    def constrain():
        resource.setrlimit(resource.RLIMIT_CPU, (cpu_limit, cpu_limit))
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                               start_new_session=True, preexec_fn=constrain)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        rows = subprocess.check_output(['ps','-axo','pid,ppid,command'],text=True).splitlines()
        descendants = {process.pid}
        parsed = [row.split(None,2) for row in rows[1:]]
        for _ in range(len(parsed)):
            added = {int(row[0]) for row in parsed if len(row)==3 and int(row[1]) in descendants}
            updated = descendants | added
            if updated == descendants:
                break
            descendants = updated
        descendants |= {int(row[0]) for row in parsed if len(row)==3 and str(work) in row[2]
                        and ('swift-frontend' in row[2] or 'swiftc' in row[2])}
        for pid in descendants:
            try:
                os.kill(pid,signal.SIGKILL)
            except ProcessLookupError:
                pass
        stdout, stderr = process.communicate()
        (work/(label+'.log')).write_text(stdout+stderr+'\nOwned compilation timed out.\n')
        records.append(dict(label=label,command=command,timeoutSeconds=timeout,cpuLimitSeconds=cpu_limit,
                            elapsedSeconds=time.monotonic()-start,exitCode=-9,terminatedPIDs=sorted(descendants)))
        (work/'runs.json').write_text(json.dumps(records,indent=2)+'\n')
        raise SystemExit('Timed out: '+label)
    result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)"""

assert source.count(needle) == 1
source = source.replace(needle, replacement)
source = source.replace('exitCode=result.returncode))', 'exitCode=result.returncode,cpuLimitSeconds=cpu_limit))')
if args.proof == 'binding':
    source = source.replace('NativePeriodicParameterFamily.swift', 'NativePeriodicBindingFailure.swift')
if args.reuse_module:
    needle = "    execute(name, common+['-parse-as-library'"
    insert = """    import shutil
    parent = Path(""" + repr(str(args.reuse_module.resolve())) + """)
    receipt_path = parent/'module-receipt.json'
    receipt = json.loads(receipt_path.read_text())
    assert receipt['lane'] == args.lane
    for path in paths:
        if digest(path) != receipt['inputs'][str(path)]:
            raise RuntimeError('Changed reused compiler input: '+str(path))
    for path, expected in receipt['products'][name].items():
        if digest(path) != expected:
            raise RuntimeError('Changed reused module product: '+path)
        shutil.copyfile(path, work/Path(path).name)
        inputs[path] = expected
    inputs[str(receipt_path)] = digest(receipt_path)
    records.append(dict(label=name, reused=True, moduleReceiptSHA256=digest(receipt_path), exitCode=0))
    (work/'runs.json').write_text(json.dumps(records,indent=2)+'\\n')
    return
"""
    assert source.count(needle) == 1
    source = source.replace(needle, insert+needle)
source_path = work/'family-driver.py'
source_path.write_text(source)
(work/'adaptation.json').write_text(json.dumps(dict(originalDriver=str(original),
    originalSHA256=hashlib.sha256(original.read_bytes()).hexdigest(),adaptedSHA256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
    excludedUnselectedLowerInputs=unselected),indent=2)+'\n')
raise SystemExit(subprocess.run(['python3',str(source_path),args.lane,'--output',str(work/'verification')],cwd=root,timeout=900).returncode)
