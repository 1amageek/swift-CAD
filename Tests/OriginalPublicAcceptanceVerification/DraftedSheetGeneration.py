"""Generate receipt-bound current modules required by the actual drafted caller."""
from pathlib import Path
import ast, hashlib, json, os, signal, subprocess, sys, time

r = Path.cwd()
lane = sys.argv[1]
out = r / '.build/drafted-sheet-20261014' / lane
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
tree = ast.parse((r / 'Tests/OriginalPublicAcceptanceVerification/NonlinearCollapseStop.py').read_text())
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run')
exec(compile(ast.Module(body=[fn], type_ignores=[]), '<bounded-run>', 'exec'))
deadline = time.monotonic() + 1200
for name, plan_name in [('CADGeometry', 'plan.json'), ('CADIR', 'IR-plan.json'), ('CADModeling', 'Modeling-plan.json')]:
    plan = json.loads((out / plan_name).read_text())
    for p, h in plan['inputs'].items():
        assert sha(p) == h, p
    command = plan['command']
    receipt = out / (name + '-generation-premises.json')
    if receipt.exists():
        cached = json.loads(receipt.read_text())
        record = json.loads((out / (name + '.json')).read_text())
        assert record['command'] == command and record['exitCode'] == 0
        assert sha(out / (name + '.log')) == record['logSHA256']
        assert cached['inputs'] == plan['inputs']
        for p, h in cached['products'].items():
            assert sha(p) == h, p
    else:
        run(command, name, seconds=max(1, deadline - time.monotonic()))
        products = {str(p): sha(p) for p in (out / (name + '.swiftmodule'), out / ('lib' + name + '.a'))}
        for p, h in plan['inputs'].items():
            assert sha(p) == h, p
        receipt.write_text(json.dumps(dict(inputs=plan['inputs'], products=products,
            recordSHA256=sha(out / (name + '.json')), scope=plan['scope']), indent=2) + '\n')
