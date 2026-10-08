#!/usr/bin/env python3
"""Measure identical public fixtures in fresh processes, retaining raw outputs."""
import hashlib,json,pathlib,statistics,subprocess,sys,time
root=pathlib.Path(__file__).resolve().parents[3]
phase,artifact_root=sys.argv[1],pathlib.Path(sys.argv[2])
out=root/'Tests/NativeExactRelationVerification/PreparationEvidence'
out.mkdir(exist_ok=True)
runner=root/'Tests/L1PolynomialVerification/Scripts/RunWASI.mjs'
measurements={}
if phase == 'paired':
 baseline=json.loads((out/'before.json').read_text())
 results={}
 for lane in ['native','embedded']:
  before=baseline[lane]['command']
  after_product=root/'.build'/('native-exact-'+lane)/'out/Products'/('Debug' if lane=='native' else 'Debug-webassembly-wasm32')
  after_binary=after_product/('NativeExactProof' if lane=='native' else 'NativeExactProof.wasm')
  after=[str(after_binary)] if lane=='native' else ['/usr/local/bin/node',str(runner),str(after_binary)]
  if hashlib.sha256(pathlib.Path(before[-1]).read_bytes()).hexdigest() != baseline[lane]['artifactSHA256']:
   raise RuntimeError('Baseline artifact changed: '+lane)
  samples={'before':[], 'after':[]}
  pairs=[]
  for iteration in range(3):
   pair={}
   for label in (['before','after'] if iteration % 2 == 0 else ['after','before']):
    command=before if label=='before' else after
    start=time.perf_counter()
    completed=subprocess.run([str(root/'scripts/swift-test-timeout.sh'),'120','--',*command],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    elapsed=time.perf_counter()-start
    (out/('paired-'+lane+'-'+str(iteration)+'-'+label+'.log')).write_text(completed.stdout)
    if completed.returncode or 'PASS Native folded SSI' not in completed.stdout or 'PASS scalar authority provenance' not in completed.stdout:
     raise RuntimeError('Fixture failure: '+lane+' '+label)
    samples[label].append(elapsed); pair[label]=elapsed
    print('paired',lane,iteration,label,round(elapsed,3),flush=True)
   pair['afterBeforeRatio']=pair['after']/pair['before']; pairs.append(pair)
  results[lane]={'pairs':pairs,'samplesSeconds':samples,
   'mediansSeconds':{label:statistics.median(values) for label,values in samples.items()},
   'commands':{'before':before,'after':after},
   'artifactSHA256':{'before':baseline[lane]['artifactSHA256'],'after':hashlib.sha256(after_binary.read_bytes()).hexdigest()}}
 (out/'paired.json').write_text(json.dumps(results,indent=2)+'\n')
 sys.exit(0)
for lane in ['native','wasm','embedded']:
 product=artifact_root/'.build'/('native-exact-'+lane)/'out/Products'/('Debug' if lane=='native' else 'Debug-webassembly-wasm32')
 binary=product/('NativeExactProof' if lane=='native' else 'NativeExactProof.wasm')
 command=[str(binary)] if lane=='native' else ['/usr/local/bin/node',str(runner),str(binary)]
 samples=[]
 for iteration in range(3):
  start=time.perf_counter()
  completed=subprocess.run([str(root/'scripts/swift-test-timeout.sh'),'120','--',*command],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  elapsed=time.perf_counter()-start
  (out/(phase+'-'+lane+'-'+str(iteration)+'.log')).write_text(completed.stdout)
  if completed.returncode or 'PASS Native folded SSI' not in completed.stdout or 'PASS scalar authority provenance' not in completed.stdout:
   raise RuntimeError('Fixture failure: '+phase+' '+lane)
  samples.append(elapsed)
  print(phase,lane,iteration,round(elapsed,3),flush=True)
 measurements[lane]={'samplesSeconds':samples,'medianSeconds':statistics.median(samples),'artifactSHA256':hashlib.sha256(binary.read_bytes()).hexdigest(),'command':command}
(out/(phase+'.json')).write_text(json.dumps(measurements,indent=2)+'\n')
