import hashlib,json,subprocess,time
from pathlib import Path
original=Path('/private/tmp/cad-m4-m8-completion-20261010')
current=Path('/private/tmp/cad-m6-native-consumer-integration-20261010')
relative=Path('Tests/OriginalNativeConsumerIntakeVerification/Evidence')
out=current/relative/'main-integration'
out.mkdir(parents=True,exist_ok=False)
checks={};sources=set();manifests={};counts={};runs=[]
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def admit(values,source=False):
 for name,expected in values.items():
  p=Path(name)
  if source and p.is_relative_to(original) and not p.is_relative_to(original/'.build'):
   p=current/p.relative_to(original);sources.add(str(p))
  key=str(p)
  if key in checks and checks[key]!=expected:raise RuntimeError('Conflicting receipts: '+key)
  checks[key]=expected
for lane in ['native','asan','wasm','embedded']:
 upper=original/relative/('consumer-'+lane+'-stable');lower=original/relative/(lane+'-query-field-accepted')
 r=json.loads((upper/'receipt.json').read_text());g=json.loads((lower/'generation.json').read_text());lr=json.loads((lower/'receipt.json').read_text())
 for p in [upper/'receipt.json',lower/'generation.json',lower/'receipt.json']:
  manifests[str(current/p.relative_to(original))]=digest(p)
 assert all(x['exitCode']==0 for x in r['runs']) and g['success'] and lr['success']
 for group in [r['inputs'],r['premises'],g['inputs']]:admit(group,True)
 for group in [r['cached'],r['artifacts'],r['products'],g['artifacts'],g['logs']]:admit(group)
 admit({str(upper/k):v for k,v in r['logs'].items()})
 admit({str(upper/'driver.py'):r['driverSHA256']})
 for name,expected in lr.get('logs',{}).items():
  p=Path(name);p=p if p.is_absolute() else lower/p;admit({str(p):expected})
 if lane in ['wasm','embedded']:
  for p in [Path('/usr/local/bin/node'),original/'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs']:
   admit({str(p):lr['inputs'][str(p)]},True)
 counts[lane]={'currentInputUnion':len(set(r['inputs'])|set(r['premises'])),'lowerInputs':len(g['inputs']),'lowerArtifacts':len(g['artifacts']),'groups':9}
for name,expected in manifests.items():assert digest(name)==expected,name
for name,expected in checks.items():assert digest(name)==expected,name
print('PRE',len(sources),'current sources',len(checks),'unique inputs/artifacts/logs PASS',flush=True)
for lane,product,group in [('native','SelfProof','folded'),('native','BoundaryProof','failures'),('embedded','SelfProof.wasm','folded')]:
 directory=original/relative/('consumer-'+lane+'-stable');binary=directory/product
 command=[str(binary),group] if lane=='native' else ['/usr/local/bin/node',str(current/'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'),str(binary),group]
 before=time.monotonic();result=subprocess.run(command,cwd=current,capture_output=True,text=True,timeout=120)
 name=lane+'-'+group+'.log';(out/name).write_text(result.stdout+result.stderr)
 runs.append({'command':command,'timeoutSeconds':120,'elapsedSeconds':time.monotonic()-before,'exitCode':result.returncode,'log':name,'logSHA256':digest(out/name),'productSHA256':digest(binary)})
 print(lane,group,result.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 if result.returncode:raise RuntimeError('Integration runtime failure: '+name)
for name,expected in checks.items():assert digest(name)==expected,name
for name,expected in manifests.items():assert digest(name)==expected,name
script=out/'VerifyIntegration.py';script.write_bytes(Path(__file__).read_bytes())
record={'success':True,'implementationCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=current,text=True).strip(),'integrationRoot':str(current),'receiptSHA256':manifests,'uniqueCheckedFiles':len(checks),'currentSourceInputs':len(sources),'currentSourceMapSHA256':hashlib.sha256(json.dumps({p:checks[p] for p in sorted(sources)},sort_keys=True).encode()).hexdigest(),'laneCounts':counts,'driverSHA256':digest(script),'runs':runs,'scope':'Independent latest-main input/artifact/log matching and fresh Native folded/public boundary failure plus Embedded folded normalization. No rebuild. Node and runner are admitted against retained lower runtime receipts before execution. ASAN instrumentation scope remains new modules plus independent lower only. General M4-M8 remains open.'}
(out/'integration.json').write_text(json.dumps(record,indent=2)+'\n')
print('POST all premises unchanged PASS',flush=True)
