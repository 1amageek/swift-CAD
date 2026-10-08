#!/usr/bin/env python3
"""Compare identical public fixtures in alternating fresh processes."""
import hashlib,json,pathlib,statistics,subprocess,time
root=pathlib.Path(__file__).resolve().parents[3]
before=pathlib.Path('/private/tmp/cad-exact-native-preparation-20261008')
out=root/'Tests/HeapPSCVerification/Evidence'
runner=root/'Tests/L1PolynomialVerification/Scripts/RunWASI.mjs'
for p in (root/'Tests/NativeExactRelationVerification/Sources/Fixtures').glob('*.swift'):
 if p.read_bytes() != (before/p.relative_to(root)).read_bytes():raise RuntimeError('Changed public fixture: '+str(p))
results={}
for lane in ['native','wasm','embedded']:
 commands={}; hashes={}
 for label,workspace in [('before',before),('after',root)]:
  product=workspace/'.build'/('native-exact-'+lane)/'out/Products'/('Debug' if lane=='native' else 'Debug-webassembly-wasm32')
  binary=product/('NativeExactProof' if lane=='native' else 'NativeExactProof.wasm')
  commands[label]=[str(binary)] if lane=='native' else ['/usr/local/bin/node',str(runner),str(binary)]
  hashes[label]=hashlib.sha256(binary.read_bytes()).hexdigest()
 samples={'before':[],'after':[]}
 for iteration in range(3):
  for label in (['before','after'] if iteration%2==0 else ['after','before']):
   start=time.perf_counter()
   done=subprocess.run([str(root/'scripts/swift-test-timeout.sh'),'120','--',*commands[label]],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
   elapsed=time.perf_counter()-start
   (out/('public-'+lane+'-'+str(iteration)+'-'+label+'.log')).write_text(done.stdout)
   if done.returncode or 'PASS Native folded SSI' not in done.stdout or 'PASS scalar authority provenance' not in done.stdout:raise RuntimeError('Failed public fixture: '+lane+' '+label)
   samples[label].append(elapsed)
   print(lane,iteration,label,round(elapsed,3),flush=True)
 results[lane]={'commands':commands,'artifactSHA256':hashes,'samplesSeconds':samples,'mediansSeconds':{k:statistics.median(v) for k,v in samples.items()}}
 (out/'public-performance.json').write_text(json.dumps(results,indent=2)+'\n')
