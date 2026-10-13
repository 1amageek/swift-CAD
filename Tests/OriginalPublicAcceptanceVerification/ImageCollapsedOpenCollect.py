"""Admit the actual complete half-open singular self-contact cell on four targets."""
from pathlib import Path
import hashlib,json,shutil
r=Path.cwd();cache=r/'.build/image-collapsed-open-20261013';e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-IMAGE-COLLAPSED-OPEN-01';e.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();save=lambda p,d:p.write_text(json.dumps(d,indent=2)+'\n')
prior=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/F1/current'
sources=json.loads((prior/'source-premises.json').read_text())
for p,h in sources.items():assert sha(r/p)==h,p
for p,h in json.loads((prior/'products.json').read_text()).items():assert sha(p)==h,p
save(e/'source-premises.json',sources);products={};lanes={}
markers={'complete':'PASS complete image singular terminal iff','controls':'PASS image swapped open scope both directions','exact':'PASS image exact query workN/storageN','work':'PASS image workN-1 typed refusal','storage':'PASS image storageN-1 typed refusal','cancel':'PASS image entry and final-publication cancellation','empty':'PASS complete image empty singleton requested product'}
for lane in ['native','asan','wasm','embedded']:
    b=cache/lane;dest=e/'accepted'/lane;dest.mkdir(parents=True,exist_ok=True)
    summary=json.loads((b/'summary.json').read_text());assert summary['status']=='PASS'and summary['groups']==list(markers)
    d=json.loads((b/'premises.json').read_text());assert d.pop('sources')==sources
    for p,h in d['checks'].items():assert sha(p)==h,p
    products.update(d['checks']);d['sourcePremisesSHA256']=sha(e/'source-premises.json');d['rawReceiptSHA256']=sha(b/'premises.json');save(dest/'premises.json',d)
    elapsed=0
    for stage in ['compile',*markers]:
        p=b/(stage+'.json');record=json.loads(p.read_text());assert record['exitCode']==0 and record['stopReason']is None
        assert sha(b/(stage+'.log'))==record['logSHA256']
        if stage in markers:
            log=(b/(stage+'.log')).read_text();assert markers[stage]in log and 'OBSERVED STOP'not in log
            if stage=='empty':assert 'PASS complete image empty final-publication cancellation'in log
            elapsed+=record['elapsedSeconds']
        shutil.copyfile(p,dest/p.name);shutil.copyfile(b/(stage+'.log'),dest/(stage+'.log'))
    lanes[lane]=dict(groups=list(markers),queryBoundary=summary['queryBoundary'],elapsedSeconds=elapsed,premisesSHA256=sha(dest/'premises.json'))
for name in ['ImageCollapsedOpenAcceptance.swift','ImageCollapsedOpenAcceptance.py','ImageCollapsedOpenCollect.py']:
    p=r/'Tests/OriginalPublicAcceptanceVerification'/name;products[str(p)]=sha(p)
protected=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/protected-before-delivery.json').read_text())
for p,h in protected.items():assert sha(p)==h,p
save(e/'products.json',products)
save(e/'summary.json',dict(status='PASS',sourceCount=len(sources),productCount=len(products),sourcePremisesSHA256=sha(e/'source-premises.json'),productsSHA256=sha(e/'products.json'),inheritedCurrentCompositionProductsSHA256=sha(prior/'products.json'),lanes=lanes,protectedFileCount=len(protected),wholeSevenCompleted=1,wholeSevenTotal=7,full87Complete=False))
print('PASS singular four lanes',len(sources),'sources',len(products),'products',flush=True)
