"""Admit current four-lane source, artifact, command and behavioral receipts."""
from pathlib import Path
import hashlib,json,shutil,subprocess
r=Path.cwd();cache=r/'.build/periodic-offset-cs-20261013';e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-OFFSET-PERIODIC-ZERO-GEOM-01'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n')
inputs={str(p.relative_to(r)):sha(p)for name in ['CADCore','CADGeometry']for p in (r/'Sources'/name).rglob('*.swift')}
save(e/'source-premises.json',inputs);sourceSHA=sha(e/'source-premises.json')
expected={str(r/p):h for p,h in inputs.items()if p.startswith('Sources/CADGeometry/')}
groups=['success','cycles','requests','empty','bare','resources','limits','cancel','lifetime'];products={};lanes={}
for lane in ['native','asan','wasm','embedded']:
    b=cache/lane;runtime=b/'accept-final'if lane=='native'else b;dest=e/'accepted'/lane;dest.mkdir(parents=True,exist_ok=True)
    premises=json.loads((runtime/'premises.json').read_text())
    for p,h in premises['checks'].items():assert sha(p)==h,p
    products.update(premises['checks']);shutil.copyfile(runtime/'premises.json',dest/'premises.json')
    if 'inputs'in premises:assert premises['inputs']==expected
    stages=['module','objects']+([]if lane=='native'else['fixture'])
    for stage in stages:
        path=b/(stage+'.json');d=json.loads(path.read_text());assert d['exitCode']==0 and d.pop('inputs')==expected
        assert sha(b/(stage+'.log'))==d['logSHA256']
        d.update(rawReceiptSHA256=sha(path),sourcePremisesSHA256=sourceSHA);save(dest/(stage+'.json'),d);shutil.copyfile(b/(stage+'.log'),dest/(stage+'.log'))
    if lane=='native':shutil.copyfile(runtime/'compile.log',dest/'compile.log')
    elapsed=0
    for group in groups:
        p=runtime/(group+'.json');d=json.loads(p.read_text());assert d['exitCode']==0 and sha(runtime/(group+'.log'))==d['logSHA256']
        assert 'PASS '+group in (runtime/(group+'.log')).read_text(),(lane,group)
        if 'inputs'in d:assert d.pop('inputs')==expected
        d.update(rawReceiptSHA256=sha(p),sourcePremisesSHA256=sourceSHA,environment={'CAD_PROOF_GROUP':group})
        save(dest/(group+'.json'),d);shutil.copyfile(runtime/(group+'.log'),dest/(group+'.log'));elapsed+=d['elapsedSeconds']
    lanes[lane]=dict(groups=groups,elapsedSeconds=elapsed,premisesSHA256=sha(dest/'premises.json'))
compat=cache/'compatibility';d=json.loads((compat/'receipt.json').read_text());assert d['status']=='PASS'
for p,h in d['checks'].items():assert sha(p)==h,p
for record in d['records']:assert record['exitCode']==0
products.update(d['checks']);dest=e/'accepted/compatibility';dest.mkdir(exist_ok=True)
lower=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-ROLLING-BALL-PLANE-01/accepted/standalone-l0/receipt.json'
for p,h in json.loads(lower.read_text())['checks'].items():assert sha(p)==h,p
products.update(json.loads(lower.read_text())['checks'])
for p in compat.iterdir():
    if p.suffix in ['.json','.log','.swift']:shutil.copyfile(p,dest/p.name)
coons=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance';external=json.loads((coons/'audit.json').read_text())['externalProducts'];protected=json.loads((coons/'protected-before-delivery.json').read_text())
for checks in [external,protected,products]:
    for p,h in checks.items():assert sha(p)==h,p
save(e/'products.json',products)
save(e/'summary.json',dict(status='PASS',lanes=lanes,sourceCount=len(inputs),sourcePremisesSHA256=sourceSHA,productsSHA256=sha(e/'products.json'),compatibilityReceiptSHA256=sha(dest/'receipt.json'),inheritedExternalProducts=len(external),protectedFileCount=len(protected),toolchain=subprocess.check_output(['/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc','--version'],text=True),wholeSevenCompleted=1,wholeSevenTotal=7,full87Complete=False))
print('PASS four lanes',len(inputs),'sources',len(products),'products',len(external),'external',len(protected),'protected',flush=True)
