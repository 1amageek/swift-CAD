from pathlib import Path
import re
r=Path.cwd();fixture=r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIAcceptance.swift';text=fixture.read_text();out=r/'.build/rolling-ssi-20261013/embedded/split';out.mkdir(exist_ok=True)
imports=text[:text.index('@main')]
start=text.index('    typealias Base')
oracle=text.index('    static func oracle(')
failure=text.index('    static func failure(')
query=text[start:oracle]
query=re.sub(r'^(    )(typealias|struct |final class |static func )',r'\1package \2',query,flags=re.M)
query=re.sub(r'^(        )(var ledger|init\(|mutating func |let state|let workLimit|func work|func storage|var counts)',r'\1package \2',query,flags=re.M)
query=query.replace('struct Counts: Sendable { var work = 0; var bytes = 0; var storageCalls = 0 }','struct Counts: Sendable { package var work = 0; package var bytes = 0; package var storageCalls = 0 }')
query=query.replace('struct Assertion: Error { let line: Int }','struct Assertion: Error { package let line: Int }')
(out/'RollingQuery.swift').write_text(imports+'package enum RollingQuery {\n'+query+'}\n')
body=text[oracle:failure].replace('    static func oracle','    package static func oracle').replace('require(','RollingQuery.require(')
(out/'RollingOracle.swift').write_text(imports+'import RollingQuery\npackage enum RollingOracle {\n    typealias Base = OriginalExactScalarDomain\n    typealias Field = ExactAlgebraicScalarDomain<Base>\n    typealias Admission = RollingQuery.Admission\n'+body+'}\n')
body=text[failure:]
for name in ['query','shape','plane','box','require','log']:
 body=re.sub(r'\b'+name+r'\(', 'RollingQuery.'+name+'(',body)
body=re.sub(r'\boracle\(', 'RollingOracle.oracle(',body)
body=body.replace('as Assertion','as RollingQuery.Assertion')
(out/'RollingMain.swift').write_text(imports+'import RollingQuery\nimport RollingOracle\n@main struct RollingPlaneSSIAcceptance {\n    typealias Base = OriginalExactScalarDomain\n    typealias Counter = RollingQuery.Counter\n    typealias Admission = RollingQuery.Admission\n'+body)
