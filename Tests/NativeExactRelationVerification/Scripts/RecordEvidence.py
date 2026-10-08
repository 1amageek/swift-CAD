#!/usr/bin/env python3
"""Verify complete production compiler inputs and retain one source manifest."""
import hashlib,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[3]
out=root/'Tests/NativeExactRelationVerification/PreparationEvidence'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
expected={str(p.relative_to(root)):digest(p) for module in ['CADCore','CADGeometry'] for p in sorted((root/'Sources'/module).rglob('*.swift'))}
lanes={}
for lane in ['native','asan','wasm','embedded']:
 scratch=root/'.build'/('native-exact-'+lane)
 lists=[]
 for module in ['CADCore','CADGeometry']:
  found=list(scratch.rglob(module+'.SwiftFileList'))
  if not found:raise RuntimeError('Missing actual compiler inputs: '+lane+' '+module)
  for file in found:
   paths=[pathlib.Path(x.strip().strip('"')).resolve() for x in file.read_text().splitlines() if x.strip()]
   actual={str(p.relative_to(root)) for p in paths}
   wanted={p for p in expected if p.startswith('Sources/'+module+'/')}
   if actual != wanted:raise RuntimeError('Compiler inventory mismatch: '+lane+' '+module)
   lists.append({'path':str(file.relative_to(root)),'sha256':digest(file),'sourceCount':len(paths)})
 lanes[lane]={'compilerInputs':lists}
 artifacts=[]
 for name in ['NativeExactProof.wasm','NativeExactPreparationProof.wasm','CADIntersectionPortabilitySmoke.wasm']:
  for p in scratch.rglob(name):artifacts.append({'path':str(p.relative_to(root)),'sha256':digest(p),'bytes':p.stat().st_size})
 lanes[lane]['rawArtifacts']=artifacts
manifest={'compiler':subprocess.check_output(['/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift','--version'],text=True).strip(),
 'node':subprocess.check_output(['/usr/local/bin/node','--version'],text=True).strip(),
 'SDKs':['swift-6.4.0-RELEASE_wasm','swift-6.4.0-RELEASE_wasm-embedded'],'target':'wasm32-unknown-wasip1',
 'productionSources':expected,'lanes':lanes,
 'fixtures':{str(p.relative_to(root)):digest(p) for p in sorted((root/'Tests/NativeExactRelationVerification/Sources/Fixtures').glob('*.swift'))},
 'logs':{p.name:digest(p) for p in sorted(out.glob('*.log'))}}
(out/'run.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Verified complete production input sets:',len(expected),'sources across all four lanes')
