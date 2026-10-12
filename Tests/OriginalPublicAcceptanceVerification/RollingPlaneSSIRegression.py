from pathlib import Path
import json,hashlib,subprocess,os,signal,time,sys
r=Path.cwd();sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();lane=sys.argv[1];base=r/'.build/rolling-ssi-20261013'/lane;out=base/'coons-regression';out.mkdir(exist_ok=True)
proof=json.loads((base/('accept-owner/premises.json'if lane=='native'else'premises.json')).read_text())
for p,h in proof['checks'].items():assert sha(p)==h,p
fixture=out/'CoonsWitnessRegression.swift';s=(r/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIAcceptance.swift').read_text();needle='try require(receipt.pairs.count == 4)';assert needle in s;s=s.replace(needle,needle+'\n        try require(receipt.surfacePlaneSections.isEmpty)');fixture.write_text(s)
command=proof['command']if lane=='native'else json.loads((base/'fixture.json').read_text())['command'];command=command.copy();command[command.index(str(r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIAcceptance.swift'))]=str(fixture);executable=out/('Regression'if lane in ['native','asan']else'Regression.wasm');command[-1]=str(executable)
def run(c,n,env=None):
 start=time.monotonic()
 with (out/(n+'.log')).open('w')as log:
  p=subprocess.Popen(c,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  try:code=p.wait(timeout=120)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
  result=dict(command=c,exitCode=code,elapsedSeconds=time.monotonic()-start,logSHA256=sha(out/(n+'.log')),fixtureSHA256=sha(fixture))
 (out/(n+'.json')).write_text(json.dumps(result,indent=2));print(lane,n,code,round(result['elapsedSeconds'],3),flush=True)
 if code:print((out/(n+'.log')).read_text()[-3000:]);raise SystemExit(code)
run(command,'compile');proof['checks'][str(fixture)]=sha(fixture);proof['checks'][str(executable)]=sha(executable);(out/'premises.json').write_text(json.dumps(proof,indent=2))
for group in ['success','empty']:
 for p,h in proof['checks'].items():assert sha(p)==h,p
 c=[str(executable)]if lane in ['native','asan']else['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIWASI.mjs'),str(executable)]
 run(c,group,dict(os.environ,CAD_PROOF_GROUP=group))
