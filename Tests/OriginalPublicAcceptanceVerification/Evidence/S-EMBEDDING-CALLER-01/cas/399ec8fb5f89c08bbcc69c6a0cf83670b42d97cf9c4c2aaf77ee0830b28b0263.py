"""Avoid a second numeric-admission specialization in the Embedded fixture."""
from pathlib import Path
import sys

r = Path.cwd()
assert sys.argv[1] == 'embedded'
driver = r / 'Tests/OriginalPublicAcceptanceVerification/EmbeddingCallerAcceptance.py'
fixture = r / 'Tests/OriginalPublicAcceptanceVerification/EmbeddingCallerAcceptance.swift'
compact = fixture.read_text()
begin = compact.index('    static func coons() throws -> Surface3D {')
end = compact.index('    static func fold() -> Surface3D {', begin)
construction = compact[begin:end]
old = '''        var a=ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        return try ExactScalarNumericAccess.withAdmission(&a) { usage in'''
assert construction.count(old) == 1
construction = construction.replace(old, '        var usage=Usage()')
assert construction.count('        }.value\n') == 1
construction = construction.replace('        }.value\n', '')
compact = compact[:begin] + construction + compact[end:]
source = driver.read_text()
changes = {
    "out = geometry / ('caller-' + sha(fixture)[:16])": "out = geometry / ('caller-compact-' + hashlib.sha256(compact.encode()).hexdigest()[:16])",
    "frozen = out / ('Fixture-' + sha(fixture) + '.swift')": "frozen = out / ('Fixture-' + hashlib.sha256(compact.encode()).hexdigest() + '.swift')",
    'frozen.write_bytes(fixture.read_bytes())': 'frozen.write_text(compact)',
    "flags[1:1] = ['-I', str(geometry)]": "flags[1:1] = ['-I', str(geometry)]\nflags[flags.index('-num-threads') + 1] = '4'",
    'for p in (fixture, frozen, Path(__file__).resolve())': 'for p in (fixture, frozen, driver, Path(__file__).resolve())',
}
for old, new in changes.items():
    assert source.count(old) == 1, old
    source = source.replace(old, new)
exec(compile(source, str(driver), 'exec'))
