from pathlib import Path
import hashlib,json,shutil
r=Path.cwd();base=r/'.build/sphere-cone-node-cs-20261014/v4';e=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-SPHERE-CONE-NODE-01';e.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
sources=json.loads((base/'source-premises.json').read_text());products={}
for p,h in sources.items():assert sha(r/p)==h,p
for lane,d in [('native','native'),('asan','asan'),('wasm','wasm'),('embedded','embedded-portable')]:
 out=base/d;premises=json.loads((out/'accepted-premises.json').read_text());assert premises['sources']==sources
 for p,h in json.loads((out/'accepted-products.json').read_text()).items():assert sha(p)==h,p;products[p]=h
 for p in sorted(out.glob('*.json')):
  data=json.loads(p.read_text())
  if 'exitCode'in data:
   assert data['exitCode']==0,p;assert sha(p.with_suffix('.log'))==data['logSHA256'],p
  q=e/'accepted'/lane/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
  if p.with_suffix('.log').exists():shutil.copy2(p.with_suffix('.log'),q.with_suffix('.log'))
 if lane=='embedded':shutil.copy2(out/'SphereConeNodeCSAcceptance.swift',e/'accepted'/lane/'SphereConeNodeCSAcceptance.swift')
for d in ['native','asan','wasm','embedded-composed']:
 out=r/'.build/sphere-cone-node-cs-20261014/v3/codec'/d
 for p,h in json.loads((out/'accepted-products.json').read_text()).items():assert sha(p)==h,p;products[p]=h
 data=json.loads((out/'accepted-premises.json').read_text())
 for p,h in data.get('writers',data['sources']).items():assert sha(r/p)==h,p;sources[p]=h
 # Reuse the unchanged codec path after the CS-dimension getter correction.
 if d=='embedded-composed':
  old=data['sources'];current=json.loads((base/'source-premises.json').read_text())
  changed={p for p in old if old[p]!=current[p]}
  assert changed=={'Sources/CADGeometry/NativeExactRelations/OriginalSphereConeNodePlaneRelation.swift','Sources/CADGeometry/NativeExactGeometricRelations/OriginalSphereConeNodeContact.swift'},changed
 for p in sorted(out.glob('*.json')):
  data=json.loads(p.read_text())
  if 'exitCode'in data:
   assert data['exitCode']==0,p;assert sha(p.with_suffix('.log'))==data['logSHA256'],p
  q=e/'accepted'/'codec'/d/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
  if p.with_suffix('.log').exists():shutil.copy2(p.with_suffix('.log'),q.with_suffix('.log'))
 if d=='embedded-composed':
  for p in (out/'writers').glob('*.swift'):shutil.copy2(p,e/'accepted'/'codec'/d/p.name)
  shutil.copy2(out/'SphereConeNodeCodecAcceptance.swift',e/'accepted'/'codec'/d/'SphereConeNodeCodecAcceptance.swift')
compat=r/'.build/sphere-cone-node-cs-20261014/v3/compatibility-native';data=json.loads((compat/'accepted.json').read_text())
for p,h in data['sources'].items():assert sha(r/p)==h,p;sources[p]=h
for p,h in data['products'].items():
 import gzip
 file=Path(p)
 if file.exists():assert sha(file)==h,p;products[p]=h
 else:
  archive=json.loads((r/'.build/diagnostic-product-archive-20261014/manifest.json').read_text())[str(file.relative_to(r))]
  digest=hashlib.sha256()
  with gzip.open(archive['archive'],'rb')as f:
   for block in iter(lambda:f.read(1048576),b''):digest.update(block)
  assert digest.hexdigest()==h==archive['originalSHA256']
  products[archive['archive']]=sha(archive['archive'])
for p in compat.iterdir():
 if p.suffix not in ['.json','.log','.swift']:continue
 q=e/'accepted/compatibility-native'/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
for n in ['SphereConeNodeCSAcceptance.swift','SphereConeNodeCSBuild.py','SphereConeNodeCSCompatibility.py','SphereConeNodeCodecAcceptance.swift','SphereConeNodeCodecBuild.py','SphereConeNodeEmbeddedCodecBuild.py','SphereConeNodeCSReceipts.py']:
 p=r/'Tests/OriginalPublicAcceptanceVerification'/n;sources[str(p.relative_to(r))]=sha(p)
sources['Tests/OriginalPublicAcceptanceVerification/AcceptanceCells.json']=sha(r/'Tests/OriginalPublicAcceptanceVerification/AcceptanceCells.json')
# Keep accepted behavior separate from pre-existing module-reader and clock failures.
for name,out in [('embedded-reader',r/'.build/sphere-cone-node-cs-20261014/v3/codec/embedded'),('reader-control',r/'.build/sphere-cone-node-cs-20261014/v3/codec/module-reader-control'),('wasm-document-clock',r/'.build/sphere-cone-node-cs-20261014/v2/codec/wasm')]:
 q=e/'diagnostics'/name;q.mkdir(parents=True,exist_ok=True)
 for p in out.glob('*'):
  if p.suffix in ['.json','.log','.swift'] and p.name not in ['accepted-premises.json','accepted-products.json']:shutil.copy2(p,q/p.name)
reused=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-CERT-SPHERECONE-FULL-01/reused-products.json').read_text())
for p,h in reused.items():assert sha(p)==h,p
protected=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/protected-before-delivery.json').read_text())
for p,h in protected.items():assert sha(p)==h,p
for p,h in sources.items():assert sha(r/p)==h,p
for name,data in [('source-premises',sources),('products',products),('reused-products',reused),('protected-products',protected)]:
 (e/(name+'.json')).write_text(json.dumps(data,indent=2)+'\n')
print(dict(sourcePremises=len(sources),products=len(products),reused=len(reused),protected=len(protected)))
