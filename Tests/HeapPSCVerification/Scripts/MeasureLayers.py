#!/usr/bin/env python3
"""Measure the unchanged lower-layer pipeline on fixed baseline/current sources."""
import hashlib,json,pathlib,statistics,subprocess,time
root=pathlib.Path(__file__).resolve().parents[3]
before=pathlib.Path('/private/tmp/cad-exact-native-preparation-20261008')
out=root/'Tests/HeapPSCVerification/Evidence'
fixture=pathlib.Path('Tests/L4TopologyVerification/Sources/LayerBenchmark/LayerBenchmark.swift')
if (before/fixture).read_bytes() != (root/fixture).read_bytes():raise RuntimeError('Changed layer fixture')
commands={'before':str(root/'.build/heap-before/out/Products/Debug/LayerBenchmark'),'after':str(root/'.build/heap-native/out/Products/Debug/LayerBenchmark')}
samples={k:[] for k in commands}
for iteration in range(3):
 for label in (['before','after'] if iteration%2==0 else ['after','before']):
  start=time.perf_counter()
  done=subprocess.run([str(root/'scripts/swift-test-timeout.sh'),'120','--',commands[label]],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  elapsed=time.perf_counter()-start
  (out/('layer-'+str(iteration)+'-'+label+'.log')).write_text(done.stdout)
  if done.returncode or 'pipeline.total' not in done.stdout:raise RuntimeError('Failed lower fixture: '+label)
  samples[label].append(elapsed);print(iteration,label,elapsed,flush=True)
result={'fixtureSHA256':hashlib.sha256((root/fixture).read_bytes()).hexdigest(),'baselineRevision':subprocess.check_output(['git','-C',str(before),'rev-parse','HEAD'],text=True).strip(),'commands':commands,'artifactSHA256':{k:hashlib.sha256(pathlib.Path(v).read_bytes()).hexdigest() for k,v in commands.items()},'samplesSeconds':samples,'medianSeconds':{k:statistics.median(v) for k,v in samples.items()}}
(out/'layer-performance.json').write_text(json.dumps(result,indent=2)+'\n')
