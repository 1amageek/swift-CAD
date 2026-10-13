"""Admit the actual complete half-open singular self-contact cell on four targets."""
from pathlib import Path
import ast,hashlib,json,shutil
r=Path.cwd();cache=r/'.build/image-periodic-self-20261013';e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-IMAGE-PERIOD-01';e.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();save=lambda p,d:p.write_text(json.dumps(d,indent=2)+'\n')
prior=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01/F1/current'
inherited=json.loads((prior/'source-premises.json').read_text())
changed='Sources/CADGeometry/NativeExactRelations/DefaultNativeExactRelationFamilyResolver+Symbolic.swift'
prefix='#if ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION\n@testable import CADGeometry\n#endif\n'
text=(r/changed).read_text();assert text.startswith(prefix)
old=text[len(prefix):].split('\nextension DefaultNativeExactRelationFamilyResolver: NativeExactSymbolicSurfacePredicateCompiling')[0]
assert hashlib.sha256(old.encode()).hexdigest()==inherited[changed]
for p,h in inherited.items():
    if p!=changed:assert sha(r/p)==h,p
sources={str(p.relative_to(r)):sha(p)for module in ['CADCore','CADGeometry']for p in sorted((r/'Sources'/module).rglob('*.swift'))}
added=set(sources)-set(inherited)
assert added=={'Sources/CADGeometry/NativeExactRelations/'+n for n in ['NativeExactSymbolicSurfacePredicateCompiling.swift','NativeExactSymbolicSurfacePredicateFamily.swift']}|{'Sources/CADGeometry/OriginalSurfaceEmbedding/'+n for n in ['OriginalAffinePeriodicSelfContactQuerying.swift','OriginalAffinePeriodicSelfContacts.swift','DefaultOriginalAffinePeriodicSelfContactQuery.swift']}
for p,h in json.loads((prior/'products.json').read_text()).items():assert sha(p)==h,p
save(e/'source-premises.json',sources);products={};lanes={}
runner=r/'Tests/OriginalPublicAcceptanceVerification/ImagePeriodicSelfAcceptance.py'
tree=ast.parse(runner.read_text());markers=next(ast.literal_eval(node.value)for node in tree.body if isinstance(node,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='markers'for t in node.targets))
for lane in ['native','asan','wasm','embedded']:
    b=cache/lane;dest=e/'accepted'/lane;dest.mkdir(parents=True,exist_ok=True)
    summary=json.loads((b/'summary.json').read_text());assert summary['status']=='PASS'and summary['groups']==list(markers)
    d=json.loads((b/'premises.json').read_text());assert d.pop('sources')==inherited
    for p,h in d['checks'].items():assert sha(p)==h,p
    products.update(d['checks']);d['sourcePremisesSHA256']=sha(e/'source-premises.json');d['rawReceiptSHA256']=sha(b/'premises.json');save(dest/'premises.json',d)
    elapsed=0
    for stage in ['port','compile',*markers]:
        p=b/(stage+'.json');record=json.loads(p.read_text());assert record['exitCode']==0 and record['stopReason']is None
        assert sha(b/(stage+'.log'))==record['logSHA256']
        if stage in markers:
            log=(b/(stage+'.log')).read_text();assert markers[stage]in log and 'OBSERVED STOP'not in log
            if stage=='empty':assert 'PASS complete empty parent restriction and final-publication cancellation'in log
            elapsed+=record['elapsedSeconds']
        shutil.copyfile(p,dest/p.name);shutil.copyfile(b/(stage+'.log'),dest/(stage+'.log'))
    lanes[lane]=dict(groups=list(markers),queryBoundary=summary['queryBoundary'],elapsedSeconds=elapsed,premisesSHA256=sha(dest/'premises.json'))
for name in ['ImagePeriodicSelfAcceptance.swift','ImagePeriodicSelfAcceptance.py','ImagePeriodicSelfCollect.py','ImagePeriodicSelfIntegration.py']:
    p=r/'Tests/OriginalPublicAcceptanceVerification'/name;products[str(p)]=sha(p)
save(e/'legacy-symbolic-body.json',dict(baselineSHA256=inherited[changed],unchangedExistingBodySHA256=hashlib.sha256(old.encode()).hexdigest(),currentSourceSHA256=sources[changed]))
protected=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/protected-before-delivery.json').read_text())
for p,h in protected.items():assert sha(p)==h,p
save(e/'products.json',products)
save(e/'summary.json',dict(status='PASS',sourceCount=len(sources),productCount=len(products),sourcePremisesSHA256=sha(e/'source-premises.json'),productsSHA256=sha(e/'products.json'),inheritedCurrentCompositionProductsSHA256=sha(prior/'products.json'),lanes=lanes,protectedFileCount=len(protected),wholeSevenCompleted=1,wholeSevenTotal=7,full87Complete=False))
print('PASS periodic symbolic self four lanes',len(sources),'sources',len(products),'products',flush=True)
