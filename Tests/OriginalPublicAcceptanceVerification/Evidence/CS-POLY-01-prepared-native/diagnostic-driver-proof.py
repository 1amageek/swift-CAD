from pathlib import Path
import json,subprocess,time,hashlib,sys
root=Path.cwd();out=root/'.build/cs-poly-01-current-native';r=json.loads((root/'Tests/OriginalPolylineFieldFamilyVerification/Evidence/native/receipt.json').read_text())
call=next(x['command'] for x in r['runs'] if x['label']=='compile-link')
flags=call[:call.index('-I',call.index('-emit-executable')+1)] if False else next(x['command'] for x in r['runs'] if x['label']=='compile-source-domain')
flags=flags[:flags.index('-emit-library')]
adapter=Path(next(x for x in call if x.endswith('libPolylineLiftAdapters.a')))
flags[1:1]=['-I',str(out/'lift-source')]
flags+=['-I',str(out),'-I',str(adapter.parent)]
files=[]
for path in [root/'Tests/OriginalPolylineSurfaceLiftVerification/Proof.swift',root/'Tests/OriginalPolylineAtlasLiftVerification/Proof.swift']:
 q=out/('Fixture'+str(len(files))+'.swift');q.write_text(path.read_text().replace('@main struct','struct'));files.append(q)
proof=out/'Proof.swift'
s=proof.read_text();s='import Darwin\n'+s if not s.startswith('import Darwin') else s
proof.write_text(s)
archives=[str(out/'lift-source/libPolylineLiftAdapters.a') if Path(x).name == 'libPolylineLiftAdapters.a' else x for x in call if x.endswith('.a')]
cmd=[*flags,'-parse-as-library','-emit-executable','-module-name','RetainedLiftPlaneProof',str(proof),*map(str,files),str(out/'libPublicLiftPlanePort.a'),str(out/'libPublicLiftPlane.a'),*archives,'-o',str(out/'proof')]
(out/'proof-command.json').write_text(json.dumps(cmd,indent=2)+'\n')
with (out/'proof-link.log').open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('link',r.returncode,flush=True)
if r.returncode:print((out/'proof-link.log').read_text()[:18000]);raise SystemExit(r.returncode)
start=time.monotonic()
mode=sys.argv[1] if len(sys.argv)>1 else 'public'
with (out/('proof-'+mode+'-runtime.log')).open('w') as log:r=subprocess.run([str(out/'proof'),*sys.argv[1:]],stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('runtime',r.returncode,round(time.monotonic()-start,3),flush=True);print((out/('proof-'+mode+'-runtime.log')).read_text()[:18000])
(out/('proof-'+mode+'-run.json')).write_text(json.dumps({'compile':cmd,'runtime':[str(out/'proof'),*sys.argv[1:]],'timeoutSeconds':120,'exitCode':r.returncode,'elapsedSeconds':time.monotonic()-start},indent=2)+'\n')
raise SystemExit(r.returncode)
