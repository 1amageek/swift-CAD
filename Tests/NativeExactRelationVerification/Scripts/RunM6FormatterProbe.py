"""Hash-bound private production helper probe; not public consumer acceptance."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[3]
scratch = root / '.build/m6-formatter-probe'
evidence = root / 'Tests/OriginalDomainConsumerVerification/Evidence/M6/formatter'
evidence.mkdir(parents=True, exist_ok=True)
package = scratch / 'package'
source = package / 'Sources/FormatterProbe/FormatterProbe.swift'
source.parent.mkdir(parents=True, exist_ok=True)
swift = '/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift'
unicode = Path.home()/'.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle/swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

helpers = {}
for filename, name in [('CertifiedAnalyticPairPcurveAreaIntegrator.swift', 'analyticPairOptionalDiagnostic'),
                       ('CertifiedAnalyticPcurveFluxIntegrator.swift', 'analyticFluxOptionalDiagnostic')]:
    path = root/'Sources/CADTopology'/filename
    text = path.read_text()
    start = text.index('private func '+name+'<')
    body = text[start:]
    if body.count('{') != 2 or body.count('}') != 2:
        raise RuntimeError('Production helper boundary changed; inspect before probing')
    helpers[name] = {'source': str(path.relative_to(root)), 'source_sha256': digest(path),
                     'body': body, 'body_sha256': hashlib.sha256(body.encode()).hexdigest()}

(package/'Package.swift').write_text('''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name:"M6FormatterProbe", targets:[.executableTarget(name:"FormatterProbe")])
''')
base = '\n'.join(value['body'] for value in helpers.values())
entry = '''
@main enum FormatterProbe {
  static func main() {
    let doubles: [Double?] = [nil, 0.25, -2.5, -0.0, .infinity, .nan, .greatestFiniteMagnitude]
    let integers: [Int?] = [nil, 0, -7, -1000000, 1000000]
    DOUBLE_REFERENCES
    INTEGER_REFERENCES
    for index in doubles.indices {
      let value = doubles[index]
      precondition(analyticPairOptionalDiagnostic(value) == doubleReferences[index])
      precondition(analyticFluxOptionalDiagnostic(value) == doubleReferences[index])
      print("DOUBLE " + doubleReferences[index])
    }
    for index in integers.indices {
      let value = integers[index]
      precondition(analyticPairOptionalDiagnostic(value) == integerReferences[index])
      precondition(analyticFluxOptionalDiagnostic(value) == integerReferences[index])
      print("INTEGER " + integerReferences[index])
    }
    print("PASS M6 private numeric Optional production formatter probe")
  }
}
'''
source.write_text(base + entry.replace('DOUBLE_REFERENCES', 'let doubleReferences = doubles.map { String(describing:$0) }')
                      .replace('INTEGER_REFERENCES', 'let integerReferences = integers.map { String(describing:$0) }'))
commands = []

def run(command, name):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    (evidence/name).write_text(result.stdout)
    commands.append({'command': command, 'exit_code': result.returncode})
    if result.returncode:
        raise RuntimeError('Probe command failed: '+name)
    return result.stdout

native = scratch/'native'
run([swift,'build','--package-path',str(package),'--scratch-path',str(native),'-j','2'], 'native-build.log')
native_artifact = native/'out/Products/Debug/FormatterProbe'
if not native_artifact.is_file(): native_artifact = native/'debug/FormatterProbe'
native_source_hash = digest(source)
result = run([str(native_artifact)], 'native-runtime.log')
doubles = [line[7:] for line in result.splitlines() if line.startswith('DOUBLE ')]
integers = [line[8:] for line in result.splitlines() if line.startswith('INTEGER ')]
if len(doubles) != 7 or len(integers) != 5: raise RuntimeError('Incomplete Native reference output')
source.write_text(base + entry.replace('DOUBLE_REFERENCES', 'let doubleReferences = '+json.dumps(doubles))
                      .replace('INTEGER_REFERENCES', 'let integerReferences = '+json.dumps(integers)))
embedded_source_hash = digest(source)
embedded = scratch/'embedded'
run([swift,'build','--package-path',str(package),'--scratch-path',str(embedded),'-j','2',
     '--swift-sdk','swift-6.4.0-RELEASE_wasm-embedded','-Xswiftc','-whole-module-optimization',
     '-Xswiftc','-Onone','-Xswiftc','-gnone','-Xlinker',str(unicode)], 'embedded-build.log')
artifact = embedded/'wasm32-unknown-wasip1/debug/FormatterProbe.wasm'
if not artifact.is_file(): artifact = embedded/'out/Products/Debug-webassembly-wasm32/FormatterProbe.wasm'
result = run(['node',str(root/'Tests/NativeExactRelationVerification/Scripts/RunGeometricProof.mjs'),str(artifact),'all'], 'embedded-runtime.log')
if 'PASS M6 private numeric Optional production formatter probe' not in result:
    raise RuntimeError('Missing Embedded completion marker')
for helper in helpers.values():
    if digest(root/helper['source']) != helper['source_sha256']: raise RuntimeError('Production source changed during probe')
receipt = {'scope':'Source-derived private Optional numeric formatter bodies; Native differential against existing reflection format and Embedded runtime. This does not establish public Topology or boundary acceptance.',
           'helpers':helpers,'commands':commands,'native_generated_source_sha256':native_source_hash,
           'embedded_generated_source_sha256':embedded_source_hash,
           'native_artifact_sha256':digest(native_artifact),'embedded_artifact_sha256':digest(artifact),
           'compiler':subprocess.check_output([swift,'--version'],text=True,timeout=10).strip(),
           'swift_sdk':'swift-6.4.0-RELEASE_wasm-embedded','target_triple':'wasm32-unknown-wasip1',
           'unicode_data_tables_sha256':digest(unicode),'node_version':subprocess.check_output(['node','--version'],text=True,timeout=10).strip()}
(evidence/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS M6 hash-bound private numeric formatter Native/Embedded probe')
