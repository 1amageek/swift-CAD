#!/usr/bin/env python3
"""Confirm the Embedded fixture isolation finding using unchanged admitted objects."""
import argparse,hashlib,json,subprocess,time,uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);a=p.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=base/'Evidence'/('isolation-'+a.lane);out.mkdir(exist_ok=False)
scratch=root/'.build/m4-periodic-offset-isolation'/a.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
accepted=base/'Evidence'/('actual-'+a.lane)/'receipt.json';r=json.loads(accepted.read_text())
fixture=base/'ActualProof.swift';checks=dict(r['inputs']);old_expected=checks.pop(str(fixture))
old=subprocess.check_output(['git','show','b139b9bb:Tests/OriginalPeriodicOffsetVerification/ActualProof.swift'],cwd=root)
assert hashlib.sha256(old).hexdigest()==old_expected
snapshot=scratch/'OriginalActualProof.swift';snapshot.write_bytes(old);checks[str(snapshot)]=old_expected
checks.update(r['product'])
for n,h in r['logs'].items():checks[str(accepted.parent/Path(n).name)]=h
checks[str(accepted)]=digest(accepted);checks[__file__]=digest(__file__);checks[str(fixture)]=digest(fixture)
for n,h in checks.items():assert digest(n)==h,n
compile_run=next(run for run in r['runs'] if run['label']=='compile-link')
command=list(compile_run['command']);artifact=scratch/('ActualOffsetIsolation.wasm' if a.lane in ['wasm','embedded'] else 'ActualOffsetIsolation')
command[command.index('-o')+1]=str(artifact)
record={'inputs':checks,'runs':[],'scope':'Finding-only actual fixture isolation; unchanged source/DI/adapters and cached numerical objects. No production rebuild.'}
(out/'inputs.json').write_text(json.dumps(record,indent=2)+'\n')
def run(label,cmd):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:result=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 record['runs'].append(dict(label=label,command=cmd,timeoutSeconds=120,elapsedSeconds=time.monotonic()-start,exitCode=result.returncode))
 print(a.lane,label,result.returncode,round(record['runs'][-1]['elapsedSeconds'],3),flush=True)
 if result.returncode:raise SystemExit(result.returncode)
run('compile-link',command);checks[str(artifact)]=digest(artifact)
runtime=list(next(run for run in r['runs'] if run['label']=='proof')['command']);runtime[-1]=str(artifact)
for n,h in checks.items():assert digest(n)==h,n
run('proof',runtime)
for log in ['compile-link.log','proof.log']:
 text=(out/log).read_text()
 assert 'data race detected' not in text,text
 assert 'actor-isolated function' not in text,text
 assert 'null function' not in text,text
for n,h in checks.items():assert digest(n)==h,n
record.update(success=True,product={str(artifact):digest(artifact)},logs={path.name:digest(path) for path in out.glob('*.log')})
(out/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS isolation finding without actor/race/null-call diagnostics',flush=True)
