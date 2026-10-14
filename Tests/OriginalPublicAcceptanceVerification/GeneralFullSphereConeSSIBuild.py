from pathlib import Path
import ast, hashlib, json, os, shutil, signal, subprocess, sys, time

r = Path.cwd()
lane = sys.argv[1]
assert lane in ('native', 'asan', 'wasm', 'embedded')
base = r / '.build/g01-root-free-family-20261014'
out = base / ('accepted-' + lane)
out.mkdir(parents=True, exist_ok=True)
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
runner = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[runner], type_ignores=[]), 'bounded-runner', 'exec'))
description = json.loads((base / 'native/build/arm64-apple-macosx/debug/description.json').read_text())
commands = description['swiftCommands']
swiftc = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc'
flags = [swiftc, '-parse-as-library', '-swift-version', '6', '-Onone', '-whole-module-optimization', '-enable-testing']
if lane in ('native', 'asan'):
    flags += ['-target', 'arm64-apple-macosx15.0', '-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk']
    if lane == 'asan': flags += ['-sanitize=address']
else:
    sdk = Path('/Users/1amageek/Library/org.swift.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1')
    sdk_descriptor = sdk / ('embedded-swift-sdk.json' if lane == 'embedded' else 'swift-sdk.json')
    target_sdk = json.loads(sdk_descriptor.read_text())['targetTriples']['wasm32-unknown-wasip1']
    resource = sdk / target_sdk['swiftResourcesPath']
    flags += ['-target', 'wasm32-unknown-wasip1', '-sdk', str(sdk / target_sdk['sdkRootPath']), '-resource-dir', str(resource), '-static-stdlib']
    if lane == 'embedded': flags += ['-enable-experimental-feature', 'Embedded', '-num-threads', '1', '-Xfrontend', '-disable-cmo', '-Xcc', '-D__EMBEDDED_SWIFT__']

sources = {}
dependencies = []
def compile_module(name):
    info = next(v for v in commands.values() if v.get('moduleName') == name)
    paths = info['sources']
    for p in paths: sources[p] = sha(p)
    response = out / (name + '.rsp')
    response.write_text('\n'.join(json.dumps(p) for p in paths) + '\n')
    package = info['otherArguments'][info['otherArguments'].index('-package-name') + 1]
    defines = [v for v in info['otherArguments'] if v.startswith('-D') and (v != '-DNativeExchange' or lane in ('native', 'asan'))]
    features = []
    for i, value in enumerate(info['otherArguments']):
        if value in ('-enable-experimental-feature', '-enable-upcoming-feature'):
            features += [value, info['otherArguments'][i + 1]]
    command = flags + ['-package-name', package, '-I', str(out)] + defines + features
    product = out / (name + ('.a' if lane == 'embedded' else '.o'))
    emission = ['-emit-library', '-static'] if lane == 'embedded' else ['-emit-object']
    command += ['-module-name', name, '-emit-module', '-emit-module-path', str(out / (name + '.swiftmodule'))] + emission + ['@' + str(response), '-o', str(product)]
    run(command, name + '-compile', 1200)
    return product

fixture_names = ['GeneralFullSphereConeSSIAcceptance', 'FullSphereConeSSIAcceptance', 'BoundedSphereConeSSIAcceptance']
fixtures = []
for name in fixture_names:
    p = r / ('Tests/OriginalPublicAcceptanceVerification/' + name + '.swift')
    sources[str(p)] = sha(p)
    text = p.read_text()
    if name != fixture_names[0]: text = text.replace('@main struct ' + name, 'enum ' + name)
    if lane == 'embedded': text = text.replace('import CADGeometry\n', '')
    target = out / p.name
    target.write_text(text)
    fixtures.append(str(target))

if len(sys.argv) > 2 and sys.argv[2] == 'fixture-only':
    for p, h in json.loads((out / 'build-products.json').read_text()).items(): assert sha(p) == h, p
    prior = json.loads((out / 'build-sources.json').read_text())
    for p, h in prior.items(): assert sha(p) == h, p
    sources.update(prior)
    command = json.loads((out / 'public-compile.json').read_text())['command']
else:
    if lane == 'native':
        original = base / 'native'
        for p, h in json.loads((original / 'v2/products.json').read_text()).items(): assert sha(p) == h, p
        for p, h in json.loads((original / 'source-premises.json').read_text()).items():
            if p.startswith('Sources/CADCore/'): assert sha(r / p) == h, p
        modules = original / 'build/arm64-apple-macosx/debug/Modules'
        for name in ('InternalCollectionsUtilities', 'HashTreeCollections', 'CADCore'):
            info = next(v for v in commands.values() if v.get('moduleName') == name)
            for p in info['sources']: sources[p] = sha(p)
            for p in modules.glob(name + '.*'): shutil.copy2(p, out / p.name)
            product = out / (name + '.o')
            shutil.copy2(original / product.name, product)
            dependencies.append(product)
    else:
        for name in ('InternalCollectionsUtilities', 'HashTreeCollections', 'CADCore'):
            dependencies.append(compile_module(name))
    info = next(v for v in commands.values() if v.get('moduleName') == 'CADGeometry')
    geometry_sources = info['sources']
    for p in geometry_sources: sources[p] = sha(p)
    response = out / 'CADGeometry.rsp'
    response.write_text('\n'.join(json.dumps(p) for p in geometry_sources) + '\n')
    public_flags = flags + ['-package-name', 'swift_cad', '-I', str(out), '-DSWIFT_PACKAGE', '-DDEBUG']
    if lane in ('native', 'asan'): public_flags += ['-DNativeExchange']
    executable = out / ('Public.wasm' if lane in ('wasm', 'embedded') else 'Public')
    if lane == 'embedded':
        command = public_flags + ['-module-name', 'CADGeometry', '@' + str(response)] + fixtures
    else:
        geometry = out / 'CADGeometry.o'
        run(public_flags + ['-module-name', 'CADGeometry', '-emit-module', '-emit-module-path', str(out / 'CADGeometry.swiftmodule'), '-emit-object', '@' + str(response), '-o', str(geometry)], 'CADGeometry-compile', 1200)
        dependencies.append(geometry)
        command = public_flags + ['-module-name', fixture_names[0]] + fixtures
    command += [str(p) for p in dependencies] + ['-o', str(executable)]
    if lane in ('wasm', 'embedded'):
        command += ['-Xlinker', '-z', '-Xlinker', 'stack-size=67108864', '-Xclang-linker', '-resource-dir', '-Xclang-linker', str(resource / 'clang')]
        if lane == 'embedded': command += ['-L', str(sdk / 'swift.xctoolchain/usr/lib/swift_static/wasip1'), '-Xlinker', '-lc++', '-Xlinker', '-lswift_Concurrency', '-Xlinker', '-lswiftUnicodeDataTables']
    (out / 'build-sources.json').write_text(json.dumps(sources, indent=2) + '\n')
    (out / 'build-products.json').write_text(json.dumps({str(p): sha(p) for p in dependencies}, indent=2) + '\n')

run(command, 'public-compile', 1200 if lane == 'embedded' else 180)
for p, h in sources.items(): assert sha(p) == h, p
exe = command[command.index('-o') + 1]
wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
groups = sys.argv[3:] if len(sys.argv) > 3 else ['general-0', 'general-1', 'general-2', 'controls', 'full-success', 'full-endpoints', 'full-publication', 'full-prepared', 'full-terminal', 'bounded-success', 'bounded-endpoints', 'bounded-publication', 'bounded-prepared', 'bounded-terminal']
for group in groups:
    call = ['/usr/local/bin/node', str(wrapper), exe, group] if lane in ('wasm', 'embedded') else [exe, group]
    run(call, 'runtime-' + group, 180)
(out / 'accepted-products.json').write_text(json.dumps({exe: sha(exe)}, indent=2) + '\n')
