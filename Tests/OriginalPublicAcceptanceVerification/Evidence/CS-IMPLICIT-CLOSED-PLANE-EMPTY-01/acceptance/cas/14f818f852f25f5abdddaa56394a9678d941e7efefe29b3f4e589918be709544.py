from pathlib import Path
import json,hashlib,ast
R=Path('/private/tmp/cad-m4-m8-completion-20261010')
P=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v2'
O=P/'fixture-resume-v1';O.mkdir(exist_ok=True)
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(n,v):(O/n).write_text(json.dumps(v,indent=2)+'\n')
def bind(p):return dict(path=str(p),sha256=sha(p),bytes=p.stat().st_size)
p=read(P/'profile.json');prior=read(P/'receipt.json')
assert sha(P/'receipt.json')=='8aa18d72c2cdd3654748e47a9c913eff750f4392c7dee38099455251e5a3438c'
assert prior['postHashesMatch'] and not prior['success']
fixture=Path(p['fixture']['original']['path']);original=fixture.read_bytes()
assert sha(fixture)=='abc7c5921fd75f5336d142856591c3ee75c65139c89e4b42e7987a28adf95a51'
oldproof=Path(p['fixture']['preparedProof']['path']);old=oldproof.read_bytes();assert old.endswith(original)
newprefix=old[:-len(original)]+b'\nimport struct ImplicitClosedAcceptanceUpper.CurveSurfaceIntersectionResult\nimport struct ImplicitClosedAcceptanceUpper.DefaultCurveSurfaceIntersector\n'
proof=O/'Proof.swift';proof.write_bytes(newprefix+original);assert proof.read_bytes()[-len(original):]==original
cmd=read(P/'fixture1-link-command.json')
cmd=[str(proof) if v==str(oldproof) else v for v in cmd]
cmd[cmd.index('-module-cache-path')+1]=str(O/'module-cache')
cmd[cmd.index('-o')+1]=str(O/'Acceptance.wasm')
save('fixture1-link-command.json',cmd)
run=read(P/'runtime-complete-command.json');run[-2]=str(O/'Acceptance.wasm');save('runtime-complete-command.json',run)
save('preparation.json',dict(priorReceipt=bind(P/'receipt.json'),priorProfile=bind(P/'profile.json'),priorProof=bind(oldproof),proof=bind(proof),originalFixture=bind(fixture),originalSuffixByteIdentical=True,addedImports=['import struct ImplicitClosedAcceptanceUpper.CurveSurfaceIntersectionResult','import struct ImplicitClosedAcceptanceUpper.DefaultCurveSurfaceIntersector'],geometryCompile=0,source4Compile=0,upperCompile=0,reusedProducts=prior['products'],fixtureCommand=bind(O/'fixture1-link-command.json'),runtimeCommand=bind(O/'runtime-complete-command.json')))
s=(P/'ExecuteApprovedProfile.py').read_text();defs=s[s.index('def recheck('):s.index("recheck();save('execution-freeze.json'")]
header='''#!/usr/bin/env python3
"""Resume the diagnosed fixture import assembly only, reusing admitted products."""
import hashlib,json,os,resource,signal,subprocess,sys,time,traceback
from pathlib import Path
R=Path('/private/tmp/cad-m4-m8-completion-20261010')
P=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v2'
O=P/'fixture-resume-v1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def save(n,v):(O/n).write_text(json.dumps(v,indent=2)+'\\n')
def bind(p):return dict(path=str(p),sha256=sha(p),bytes=Path(p).stat().st_size)
def cpu_seconds(v):return sum(float(x)*60**i for i,x in enumerate(reversed(v.split(':'))))
assert not (O/'execution-started.json').exists(),'No blind retry'
assert sha(P/'receipt.json')=='8aa18d72c2cdd3654748e47a9c913eff750f4392c7dee38099455251e5a3438c'
p=read(P/'profile.json');prior=read(P/'receipt.json');preparation=read(O/'preparation.json')
checks=dict(prior['checks']);checks.update(prior['products'])
for f in ['preparation.json','Proof.swift','fixture1-link-command.json','runtime-complete-command.json','ExecuteFixtureResume.py']:
 checks[str(O/f)]=sha(O/f)
checks[str(P/'receipt.json')]=sha(P/'receipt.json')
products=dict(prior['products']);runs=[];geometry_start=None;geometry_cpu={};geometry_peak=0;spent_wall=0;spent_cpu=0;all_started=time.monotonic();failure=None;state='pre-admission'
GROUPS=prior['groups']
'''
footer='''
recheck();save('execution-freeze.json',dict(executor=bind(Path(__file__).resolve()),checks=checks,reusedProducts=prior['products'],groups=GROUPS,preparation=bind(O/'preparation.json'),geometryCompile=0,source4Compile=0,upperCompile=0))
if '--prepare-only' in sys.argv:
 print(json.dumps(dict(state='FROZEN-NO-COMPILER',executor=bind(Path(__file__).resolve()),freeze=bind(O/'execution-freeze.json'),checks=len(checks))),flush=True)
 raise SystemExit(0)
save('execution-started.json',dict(executorSHA256=sha(__file__),freezeSHA256=sha(O/'execution-freeze.json'),startedUnix=time.time()))
print(json.dumps(dict(state='START',stage='fixture1-link',executorSHA256=sha(__file__))),flush=True)
try:
 state='fixture1-link-started';execute('fixture1-link',read(O/'fixture1-link-command.json'));retain([O/'Acceptance.wasm']);recheck()
 print(json.dumps(dict(state='PASS',stage='fixture1-link')),flush=True)
 for group in GROUPS:
  state='runtime-'+group+'-started';cmd=read(O/'runtime-complete-command.json');cmd[-1]=group
  execute('runtime-'+group,cmd);recheck();print(json.dumps(dict(state='PASS',stage='runtime-'+group)),flush=True)
 state='all-authorized-groups-green'
except BaseException as error:
 failure=dict(type=type(error).__name__,message=str(error),traceback=traceback.format_exc());print(json.dumps(dict(state='STOP',at=state,failure=failure)),flush=True)
finally:
 try:recheck();post=True
 except BaseException as error:post=False;failure=failure or dict(type=type(error).__name__,message=str(error))
 save('receipt.json',dict(cell='CS-IMPLICIT-CLOSED-PLANE-EMPTY-01',lane='embedded',state=state,success=state=='all-authorized-groups-green' and post,cellComplete=False,executor=bind(Path(__file__).resolve()),executionFreeze=bind(O/'execution-freeze.json'),priorStoppedReceipt=bind(P/'receipt.json'),preparation=preparation,checks=checks,products=products,reusedProducts=prior['products'],runs=runs,failure=failure,postHashesMatch=post,totalElapsedSeconds=time.monotonic()-all_started,groups=GROUPS,geometryCodegen=0,source4Codegen=0,upperCodegen=0,originalFixtureSuffixByteIdentical=True,retryCount=0))
 print(json.dumps(dict(state=state,receipt=bind(O/'receipt.json'))),flush=True)
if failure:raise SystemExit(1)
'''
script=header+defs+footer;ast.parse(script);(O/'ExecuteFixtureResume.py').write_text(script)
print(json.dumps(dict(preparation=bind(O/'preparation.json'),executor=bind(O/'ExecuteFixtureResume.py'),proof=bind(proof),fixtureCommand=bind(O/'fixture1-link-command.json'))))
