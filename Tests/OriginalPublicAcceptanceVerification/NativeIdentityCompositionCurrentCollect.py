"""Freeze finding-only current-source acceptance without rewriting the historical packet."""
from pathlib import Path
import hashlib,json,shutil
r=Path.cwd();cache=r/'.build/native-identity-current-20261013-v2';e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/F1/current';e.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();save=lambda p,d:p.write_text(json.dumps(d,indent=2)+'\n')
sources=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-OFFSET-PERIODIC-ZERO-GEOM-01/source-premises.json').read_text())
for p,h in sources.items():assert sha(r/p)==h,p
save(e/'source-premises.json',sources);products={};lanes={}
groups=['complete','controls','exact','work','storage','cancel']
markers={'complete':'PASS every terminal raw/refined iff','controls':'PASS depth3/count5 exact readmission','exact':'PASS independent prepared query exact workN/storageN','work':'PASS workN-1 exact typed work refusal','storage':'PASS storageN-1 exact typed storage refusal','cancel':'PASS entry and final-publication checkpoint cancellation'}
for lane in ['native','asan','wasm','embedded']:
    b=cache/lane;dest=e/lane;dest.mkdir(exist_ok=True)
    summary=json.loads((b/'summary.json').read_text());assert summary['status']=='PASS'and summary['groups']==groups
    d=json.loads((b/'premises.json').read_text());assert d.pop('sources')==sources
    for p,h in d['checks'].items():assert sha(p)==h,p
    products.update(d['checks']);d['sourcePremisesSHA256']=sha(e/'source-premises.json');d['rawReceiptSHA256']=sha(b/'premises.json');save(dest/'premises.json',d)
    stages=['compile',*groups]+(['fresh-issuer']if lane!='embedded'else[])
    elapsed=0
    for stage in stages:
        p=b/(stage+'.json');record=json.loads(p.read_text());assert record['exitCode']==0 and record['stopReason']is None
        assert sha(b/(stage+'.log'))==record['logSHA256']
        if stage in groups:
            log=(b/(stage+'.log')).read_text();assert markers[stage]in log and 'OBSERVED STOP'not in log
            elapsed+=record['elapsedSeconds']
        shutil.copyfile(p,dest/p.name);shutil.copyfile(b/(stage+'.log'),dest/(stage+'.log'))
    for p in b.rglob('*.rsp'):
        products[str(p)]=sha(p)
    if lane=='embedded':shutil.copyfile(b/'embedded-current-generation.json',dest/'embedded-current-generation.json')
    else:
        linked=[Path(json.loads(line))for line in (b/'objects.rsp').read_text().splitlines()]
        issuer=[p for p in linked if p.stem in ['DefaultOriginalParameterIdentityIssuer','DefaultOriginalParameterIdentityIssuer.swift']]
        assert issuer==[b/'DefaultOriginalParameterIdentityIssuer.o'],issuer
    lanes[lane]=dict(groups=groups,queryBoundary=summary['queryBoundary'],elapsedSeconds=elapsed,premisesSHA256=sha(dest/'premises.json'),freshIssuerBody=summary['freshIssuerBody'])
for name in ['NativeIdentityCompositionCurrent.swift','NativeIdentityCompositionCurrent.py','NativeIdentityCompositionCurrentCollect.py']:
    p=r/'Tests/OriginalPublicAcceptanceVerification'/name;products[str(p)]=sha(p)
save(e/'products.json',products)
review=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/REVIEW.md';assert sha(review)=='495f346d382c6f64e1eb370ec04e6fe5940581862ce917e32e0d187df47484c2'
protected=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/protected-before-delivery.json').read_text())
for p,h in protected.items():assert sha(p)==h,p
save(e/'summary.json',dict(status='PASS',finding='F1 closed for current Geometry source; historical independent DI packet unchanged',reviewSHA256=sha(review),sourceCount=len(sources),productCount=len(products),sourcePremisesSHA256=sha(e/'source-premises.json'),productsSHA256=sha(e/'products.json'),lanes=lanes,protectedFileCount=len(protected),wholeSevenCompleted=1,wholeSevenTotal=7,full87Complete=False))
print('PASS F1 current four lanes',len(sources),'sources',len(products),'products',flush=True)
