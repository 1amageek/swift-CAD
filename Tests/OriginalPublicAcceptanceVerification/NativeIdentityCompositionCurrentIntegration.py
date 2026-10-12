"""Audit the identical source snapshot and replay public acceptance after integration."""
from pathlib import Path
import hashlib, json, os, subprocess, sys, time
r = Path.cwd()
e = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/F1/current'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
feature = sys.argv[1]
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
assert head == feature, (head, feature)
summary = json.loads((e / 'summary.json').read_text())
assert summary['status'] == 'PASS' and len(summary['lanes']) == 4
sources = json.loads((e / 'source-premises.json').read_text())
for p, h in sources.items(): assert sha(r / p) == h, p
products = json.loads((e / 'products.json').read_text())
for p, h in products.items(): assert sha(p) == h, p
old = r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance'
external = json.loads((old / 'audit.json').read_text())['externalProducts']
for p, h in external.items(): assert sha(p) == h, p
protected = json.loads((old / 'protected-before-delivery.json').read_text())
for p, h in protected.items(): assert sha(p) == h, p
files = {str(p.relative_to(r)): sha(p) for p in e.rglob('*') if p.is_file() and p.name != 'integration.json' and p.suffix != ''}
runs = []
for lane in ['native', 'embedded']:
    proof = json.loads((e / lane / 'premises.json').read_text())
    suffix = '/Proof' if lane == 'native' else '/Proof.wasm'
    executable = next(p for p in proof['checks'] if p.endswith(suffix))
    for group in ['complete', 'controls']:
        for p, h in proof['checks'].items(): assert sha(p) == h, p
        command = [executable,group] if lane == 'native' else ['/usr/local/bin/node', str(r / 'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/cas/d28630d93d8f8d5d14997273d950d78e61189547240e18c6c28f20853c012257.mjs'), executable,group]
        start = time.monotonic()
        completed = subprocess.run(command, capture_output=True, text=True, timeout=120, env=dict(os.environ, CAD_PROOF_GROUP=group))
        assert completed.returncode == 0 and ('PASS every terminal raw/refined iff' if group=='complete' else 'PASS depth3/count5 exact readmission') in completed.stdout, completed.stdout + completed.stderr
        runs.append(dict(lane=lane, group=group, command=command, exitCode=completed.returncode, elapsedSeconds=time.monotonic()-start, stdout=completed.stdout, stderr=completed.stderr, executableSHA256=sha(executable)))
for p, h in sources.items(): assert sha(r / p) == h, p
for p, h in protected.items(): assert sha(p) == h, p
result = dict(featureCommit=feature, integratedHead=head, sourceCount=len(sources), sourcePremisesSHA256=sha(e/'source-premises.json'), productCount=len(products), inheritedExternalProductCount=len(external), protectedFiles=protected, durableEvidence=files, runtime=runs, status='PASS', wholeSevenCompleted=1, wholeSevenTotal=7, full87Complete=False)
(e / 'integration.json').write_text(json.dumps(result, indent=2) + '\n')
print('PASS integrated source', len(sources), 'products', len(products), 'external', len(external), 'protected', len(protected), flush=True)
