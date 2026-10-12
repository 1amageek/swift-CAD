from pathlib import Path
import json,hashlib,subprocess,signal,time
r=Path.cwd();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();cache=r/'.build/coons-ssi-recovery-20261012/native-public';out=r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-ROLLING-BALL-PLANE-01/red';out.mkdir(exist_ok=True)
audit=json.loads((r/'Tests/OriginalPublicAcceptanceVerification/Evidence/SSI-COONS-PLANE-01/acceptance/audit.json').read_text())
print('AUDIT_KEYS',audit.keys(),flush=True)
for key in ['productionInputs','externalProducts']:
 for p,h in audit[key].items():
  assert sha(Path(p))==h,p
old=json.loads((cache/'linked-products.json').read_text())
for p,h in old.items():
 if p.endswith('/CoonsPlaneSSIAcceptance.swift'):continue
 assert sha(Path(p))==h,p
command=json.loads((cache/'fixture-compile.json').read_text())['command'];fixture=r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIStop.swift';command=[str(fixture)if x.endswith('/CoonsPlaneSSIAcceptance.swift')else x for x in command];command[-1]=str(out/'Stop');start=time.monotonic()
with (out/'compile.log').open('w')as log: c=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=120)
assert c.returncode==0,(out/'compile.log').read_text()
with (out/'runtime.log').open('w')as log:
 p=subprocess.Popen([str(out/'Stop')],stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 try:code=p.wait(timeout=30)
 except subprocess.TimeoutExpired:os=None;import os;os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
(out/'receipt.json').write_text(json.dumps(dict(command=command,inputs={str(fixture):sha(fixture)},baselineProducts=old,executableSHA256=sha(out/'Stop'),elapsedSeconds=time.monotonic()-start,exitCode=code,logSHA256=sha(out/'runtime.log')),indent=2));print('RESULT',code,(out/'runtime.log').read_text(),flush=True)
