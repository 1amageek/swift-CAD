"""Reuse the accepted offset caller driver with the new shared Geometry owner."""
from pathlib import Path
import hashlib

r = Path.cwd()
driver = r / 'Tests/OriginalPublicAcceptanceVerification/CoonsOffsetCallerAcceptance.py'
assert hashlib.sha256(driver.read_bytes()).hexdigest() == '45847b297354af605d007768cdeec3b3c6958daa5a8e439897aa46d6e5efa17d'
source = driver.read_text()
changes = {
    "'.build/coons-offset-caller-green-20261014'": "'.build/embedding-offset-regression-v2-20261014'",
    "plan = json.loads((canonical / 'plan.json').read_text())": "generation = r / '.build/embedding-caller-v2-20261014' / lane\nplan = json.loads((generation / 'plan.json').read_text())",
    'len(geometry_inputs) == 2054': 'len(geometry_inputs) == 2056',
    "canonical / 'CADGeometry.json'": "generation / 'CADGeometry.json'",
    "canonical / 'CADGeometry.log'": "generation / 'CADGeometry.log'",
    "plan['commands']['CADGeometry']": "plan['command']",
    "geometry_products = [canonical / 'CADGeometry.swiftmodule', canonical / 'libCADGeometry.a']": "geometry_products = [generation / 'CADGeometry.swiftmodule', generation / 'libCADGeometry.a']",
    "flags[1:1] = ['-I', str(out), '-I', str(canonical)]": "flags[1:1] = ['-I', str(out), '-I', str(generation), '-I', str(canonical)]",
    "inputs = dict(geometry_inputs)": "inputs = dict(geometry_inputs)\ninputs[str(driver)] = sha(driver)",
    'Geometry2054/Topology143/Core reused': 'Geometry2056 generated; unchanged Topology143/Core reused',
    "libraries += [canonical / 'libCADGeometry.a', edge / 'libCADTopology.a']": "libraries += [generation / 'libCADGeometry.a', edge / 'libCADTopology.a']",
}
for old, new in changes.items():
    assert source.count(old) == 1, old
    source = source.replace(old, new)
exec(compile(source, str(driver), 'exec'))
