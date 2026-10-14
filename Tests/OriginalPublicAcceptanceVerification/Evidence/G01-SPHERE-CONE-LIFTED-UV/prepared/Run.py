from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time

r = Path.cwd()
lane = sys.argv[1]
assert lane in ('native', 'asan', 'wasm')
root = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/G01-SPHERE-CONE-LIFTED-UV/prepared'
out = root / lane
out.mkdir(parents=True, exist_ok=True)
base = r / '.build/g01-lifted-finite-20261014' / lane
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
sources = json.loads((base / 'source-premises.json').read_text())
products = json.loads((base / 'products.json').read_text())
def verify():
    for path, digest in sources.items():
        assert sha(path) == digest, path
    for path, digest in products.items():
        assert sha(path) == digest, path
verify()
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
runner = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[runner], type_ignores=[]), 'prepared-bounded-runner', 'exec'))
fixtures = []
for name in ('BoundedSphereConeSSIAcceptance', 'GeneralBoundedFiniteSphereConeSSIAcceptance', 'GeneralLiftedFiniteSphereConeSSIAcceptance'):
    original = r / ('Tests/OriginalPublicAcceptanceVerification/' + name + '.swift')
    text = original.read_text().replace('@main struct ' + name, 'enum ' + name)
    target = out / original.name
    target.write_text(text)
    fixtures.append(str(target))
probe = root / 'PreparedLiftedProbe.swift'
fixtures.append(str(probe))
command = json.loads((base / 'public-compile.json').read_text())['command']
command = [value for value in command if not value.endswith('.swift')]
command[command.index('-module-name') + 1] = 'PreparedLiftedProbe'
executable = out / ('PreparedLiftedProbe.wasm' if lane == 'wasm' else 'PreparedLiftedProbe')
command[command.index('-o') + 1] = str(executable)
command += fixtures
premises = dict(sourceManifestSHA256=sha(base / 'source-premises.json'),
    productManifestSHA256=sha(base / 'products.json'),
    inheritedSources=sources, inheritedProducts=products,
    probeSources={str(path): sha(path) for path in [probe, root / 'Run.py']},
    transformedFixtures={path: sha(path) for path in fixtures[:-1]})
(out / 'source-premises.json').write_text(json.dumps(premises, indent=2) + '\n')
run(command, 'compile', 180)
if lane == 'wasm':
    wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
    call = ['/usr/local/bin/node', str(wrapper), str(executable), 'lifted-prepared']
    premises['wrapperSHA256'] = sha(wrapper)
else:
    call = [str(executable), 'lifted-prepared']
run(call, 'runtime', 180)
verify()
for path, digest in premises['probeSources'].items():
    assert sha(path) == digest, path
for path, digest in premises['transformedFixtures'].items():
    assert sha(path) == digest, path
(out / 'source-premises.json').write_text(json.dumps(premises, indent=2) + '\n')
(out / 'products.json').write_text(json.dumps({str(executable): sha(executable)}, indent=2) + '\n')
(out / 'accepted-scope.json').write_text(json.dumps(dict(lane=lane, inputs=2, parentOrders=2,
    independentCycles=[[1, 0], [-2, 3]], preparedNonemptyFinite=True, detachedIndependentAdmission=True,
    counterWorkCap=8388608, counterStorageByteCap=268435456,
    productionRecompiled=False, embeddedCoverage=False), indent=2) + '\n')
