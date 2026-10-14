from pathlib import Path
import ast, hashlib, json, os, shutil, signal, subprocess, sys, time

r = Path.cwd()
lane = sys.argv[1]
assert lane in ('native', 'asan', 'wasm', 'embedded')
base = r / '.build/g01-bounded-family-20261014'
out = base / lane
out.mkdir(parents=True, exist_ok=True)
lane_evidence = r / ('Tests/OriginalPublicAcceptanceVerification/Evidence/G01-SPHERE-CONE-ROOTFREE/' + lane)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
runner = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[runner], type_ignores=[]), 'bounded-runner', 'exec'))

dependencies = {}
for path, digest in json.loads((lane_evidence / 'products.json').read_text()).items():
    source = Path(path)
    if source.stem in ('CADCore', 'HashTreeCollections', 'InternalCollectionsUtilities'):
        assert sha(source) == digest, source
        target = out / source.name
        shutil.copy2(source, target)
        dependencies[str(target)] = digest
source_evidence = json.loads((lane_evidence.parent / 'source-premises.json').read_text())
for path, digest in source_evidence.items():
    if '/Sources/CADCore/' in path or '/checkouts/' in path: assert sha(path) == digest, path

sources = {str(p): sha(p) for p in sorted((r / 'Sources/CADGeometry').rglob('*.swift'))}
response = out / 'CADGeometry.rsp'
response.write_text('\n'.join(json.dumps(path) for path in sources) + '\n')
fixture_names = ['GeneralFullSphereConeSSIAcceptance', 'FullSphereConeSSIAcceptance',
                 'BoundedSphereConeSSIAcceptance', 'GeneralBoundedSphereConeSSIAcceptance',
                 'GeneralBoundedSphereConeSSIControls', 'PureSquareRootAdmissionAcceptance']
fixtures = []
for name in fixture_names:
    source = r / ('Tests/OriginalPublicAcceptanceVerification/' + name + '.swift')
    sources[str(source)] = sha(source)
    text = source.read_text()
    if name != fixture_names[0]: text = text.replace('@main struct ' + name, 'enum ' + name)
    if lane == 'embedded': text = text.replace('@testable import CADGeometry\n', '').replace('import CADGeometry\n', '')
    target = out / source.name
    target.write_text(text)
    fixtures.append(str(target))

record = lane_evidence / ('public-compile.json' if lane == 'embedded' else 'CADGeometry-compile.json')
command = json.loads(record.read_text())['command']
command[1:1] = ['-I', str(out)]
command = [v for v in command if not v.endswith('.swift')]
command[next(i for i, v in enumerate(command) if v.startswith('@'))] = '@' + str(response)
executable = out / ('Public.wasm' if lane in ('wasm', 'embedded') else 'Public')
if lane == 'embedded':
    command += ['-DG01_BOUNDED_ACCEPTANCE'] + fixtures
    for i, value in enumerate(command):
        if value in json.loads((lane_evidence / 'products.json').read_text()):
            if Path(value).stem in ('CADCore', 'HashTreeCollections', 'InternalCollectionsUtilities'):
                command[i] = str(out / Path(value).name)
    command[command.index('-o') + 1] = str(executable)
else:
    command += ['-no-emit-module-separately-wmo']
    command[command.index('-emit-module-path') + 1] = str(out / 'CADGeometry.swiftmodule')
    command[command.index('-o') + 1] = str(out / 'CADGeometry.o')
    if lane == 'native':
        previous = r / '.build/g01-chart-domain-20261014/bounded-native-v11'
        for path, digest in json.loads((previous / 'source-premises.json').read_text()).items(): assert sha(path) == digest, path
        for path, digest in json.loads((previous / 'compile-products.json').read_text()).items():
            assert sha(path) == digest, path
            shutil.copy2(path, out / Path(path).name)
    else:
        run(command, 'geometry-compile', 1200)
    dependencies.update({str(out / name): sha(out / name) for name in ('CADGeometry.swiftmodule', 'CADGeometry.o')})
    public = json.loads((lane_evidence / 'public-compile.json').read_text())['command']
    public = [v for v in public if not v.endswith('.swift')]
    public[1:1] = ['-I', str(out)]
    for i, value in enumerate(public):
        if value.endswith('.o') and Path(value).stem in ('CADGeometry', 'CADCore', 'HashTreeCollections', 'InternalCollectionsUtilities'):
            public[i] = str(out / Path(value).name)
    public[public.index('-o') + 1] = str(executable)
    command = public + ['-DG01_BOUNDED_ACCEPTANCE'] + fixtures

run(command, 'public-compile', 1200 if lane == 'embedded' else 180)
for path, digest in sources.items(): assert sha(path) == digest, path
for path, digest in dependencies.items(): assert sha(path) == digest, path
(out / 'source-premises.json').write_text(json.dumps(sources, indent=2) + '\n')
(out / 'products.json').write_text(json.dumps(dependencies | {str(executable): sha(executable)}, indent=2) + '\n')
wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
groups = sys.argv[2:] or ['bounded-success', 'bounded-endpoints', 'pure-square', 'bounded-general-0', 'bounded-general-1',
                         'bounded-general-2', 'bounded-controls', 'general-0', 'general-1', 'general-2', 'controls',
                         'full-success', 'full-endpoints', 'full-publication', 'full-prepared', 'full-terminal',
                         'bounded-publication', 'bounded-prepared', 'bounded-terminal']
for group in groups:
    call = ['/usr/local/bin/node', str(wrapper), str(executable), group] if lane in ('wasm', 'embedded') else [str(executable), group]
    run(call, 'runtime-' + group, 180)
(out / 'accepted-groups.json').write_text(json.dumps(groups, indent=2) + '\n')
