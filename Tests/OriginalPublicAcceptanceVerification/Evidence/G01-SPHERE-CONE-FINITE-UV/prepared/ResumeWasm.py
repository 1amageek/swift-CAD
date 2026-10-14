from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, time

r = Path.cwd()
lane = 'wasm'
root = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/G01-SPHERE-CONE-FINITE-UV/prepared'
out = root / lane
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
premises = json.loads((out / 'source-premises.json').read_text())
def verify():
    for group in ('inheritedSources', 'inheritedProducts', 'probeSources', 'transformedFixtures'):
        for path, digest in premises[group].items():
            assert sha(path) == digest, path
verify()
assert json.loads((out / 'compile.json').read_text())['exitCode'] == 0
executable = out / 'PreparedFiniteProbe.wasm'
executable_sha = sha(executable)
script = root / 'ResumeWasm.py'
premises['probeSources'][str(script)] = sha(script)
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
runner = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[runner], type_ignores=[]), 'prepared-bounded-wasm-runner', 'exec'))
wrapper = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'
premises['wrapperSHA256'] = sha(wrapper)
run(['/usr/local/bin/node', str(wrapper), str(executable), 'prepared-finite'], 'runtime-prepared', 180)
verify()
assert sha(executable) == executable_sha
(out / 'source-premises.json').write_text(json.dumps(premises, indent=2) + '\n')
(out / 'products.json').write_text(json.dumps({str(executable): executable_sha}, indent=2) + '\n')
(out / 'accepted-scope.json').write_text(json.dumps(dict(lane=lane, inputs=3, parentOrders=2,
    endpointConeU=[1, 2], preparedNonemptyFinite=True, detachedIndependentAdmission=True,
    counterWorkCap=8388608, counterStorageByteCap=268435456,
    productionRecompiled=False, embeddedCoverage=False,
    acceptedRuntime='runtime-prepared.json', preservedLaunchFailure='runtime.json'), indent=2) + '\n')
