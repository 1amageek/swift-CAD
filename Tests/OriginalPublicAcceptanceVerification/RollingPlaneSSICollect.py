from pathlib import Path
import json,hashlib,shutil,subprocess
r=Path.cwd();cache=r/'.build/rolling-ssi-20261013';e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-ROLLING-BALL-PLANE-01';sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n');e.mkdir(exist_ok=True)
inputs={str(p.relative_to(r)):sha(p)for d in ['CADCore','CADGeometry']for p in (r/'Sources'/d).rglob('*.swift')};save(e/'source-premises.json',inputs);sourceSHA=sha(e/'source-premises.json')
groups=['success','requests','empty','bare','resources','limits','scalar','cancel','lifetime'];products={};lanes={}
for lane in ['native','asan','wasm','embedded']:
 b=cache/lane;runtime=b/'accept-owner'if lane=='native'else b
 if not (runtime/'lifetime.json').exists():continue
 dest=e/'accepted'/lane;dest.mkdir(parents=True,exist_ok=True)
 premises=json.loads((runtime/'premises.json').read_text())
 for p,h in premises['checks'].items():assert sha(p)==h,p
 products.update(premises['checks']);shutil.copyfile(runtime/'premises.json',dest/'premises.json')
 expected={str(r/p):h for p,h in inputs.items()if p.startswith('Sources/CADGeometry/')}
 stages=['frontend-module','frontend-objects','fixture-parallel']if lane=='embedded'else(['module','objects','fixture']if lane!='native'else['module','objects'])
 for stage in stages:
  path=b/(stage+'.json');d=json.loads(path.read_text());assert d['exitCode']==0 and d['inputs']==expected
  original=sha(path);d.pop('inputs');d.update(rawReceiptSHA256=original,sourcePremisesSHA256=sourceSHA)
  save(dest/(stage+'.json'),d);shutil.copyfile(b/(stage+'.log'),dest/(stage+'.log'))
 elapsed=0
 for group in groups:
  p=runtime/(group+'.json');d=json.loads(p.read_text());assert d['exitCode']==0 and sha(runtime/(group+'.log'))==d['logSHA256']
  assert ('PASS '+group) in (runtime/(group+'.log')).read_text(),(lane,group)
  if 'inputs'in d:assert d.pop('inputs')==expected
  d.update(rawReceiptSHA256=sha(p),sourcePremisesSHA256=sourceSHA,environment={'CAD_PROOF_GROUP':group});save(dest/(group+'.json'),d);shutil.copyfile(runtime/(group+'.log'),dest/(group+'.log'));elapsed+=d['elapsedSeconds']
 lanes[lane]=dict(groups=groups,elapsedSeconds=elapsed,premisesSHA256=sha(dest/'premises.json'))
 reg=b/'coons-regression'
 if lane=='native' and (reg/'empty.json').exists():
  dd=dest/'coons-regression';dd.mkdir(exist_ok=True)
  for n in ['CoonsWitnessRegression.swift','premises.json','compile.json','compile.log','success.json','success.log','empty.json','empty.log']:shutil.copyfile(reg/n,dd/n)
for name in ['fixture.json','RollingQuery.json']:
 p=cache/'embedded'/name
 if p.exists():
  d=json.loads(p.read_text());assert d['exitCode']!=0;d.pop('inputs',None);save(e/'diagnostics'/('embedded-'+name),d);shutil.copyfile(p.with_suffix('.log'),e/'diagnostics'/('embedded-'+p.with_suffix('.log').name))
for name in ['graph-probe.log','graph-probe2.log','graph-probe3.log','graph-probe4.log','graph-probe5.log']:
 if (cache/'native'/name).exists():shutil.copyfile(cache/'native'/name,e/'diagnostics'/name)
for p in [cache/'native/accept-singleton/limits.log',cache/'native/accept-controls/cancel.log']:
 if p.exists():shutil.copyfile(p,e/'diagnostics'/(p.parent.name+'-'+p.name))
coons=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/audit.json';old=json.loads(coons.read_text())
for p,h in old['externalProducts'].items():assert sha(p)==h,p
for p,h in products.items():assert sha(p)==h,p
save(e/'products.json',products)
save(e/'summary.json',dict(status='PASS'if len(lanes)==4 else'PENDING',lanes=lanes,sourcePremisesSHA256=sourceSHA,productsSHA256=sha(e/'products.json'),coonsDependencyAuditSHA256=sha(coons),inheritedExternalProducts=len(old['externalProducts']),toolchain=subprocess.check_output(['/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc','--version'],text=True),wholeSevenCompleted=1,wholeSevenTotal=7,full87Complete=False))
print('COLLECTED',list(lanes),len(inputs),len(products),flush=True)
