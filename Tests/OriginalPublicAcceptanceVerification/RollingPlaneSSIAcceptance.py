from pathlib import Path
import json,hashlib,subprocess,signal,os,time,sys
r=Path.cwd();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();base=r/'.build/rolling-ssi-20261013/native';out=base/('accept-'+sys.argv[1]);out.mkdir(exist_ok=True)
for p,h in json.loads((base/'linked-products.json').read_text()).items():assert sha(Path(p))==h,p
for p,h in json.loads((base/'objects.json').read_text())['inputs'].items():assert sha(Path(p))==h,p
c=json.loads((base/'fixture.json').read_text())['command'];c=[x.replace('RollingPlaneSSIStop.swift','RollingPlaneSSIAcceptance.swift')for x in c];c[-1]=str(out/'Acceptance')
with (out/'compile.log').open('w')as log:p=subprocess.run(c,stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('compile',p.returncode,flush=True)
if p.returncode:print((out/'compile.log').read_text()[-3000:]);raise SystemExit(1)
fixture=r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIAcceptance.swift';checks={str(fixture):sha(fixture),str(out/'Acceptance'):sha(out/'Acceptance')};checks.update(json.loads((base/'linked-products.json').read_text()))
(out/'premises.json').write_text(json.dumps(dict(checks=checks,command=c,sourceReceiptSHA256=sha(base/'objects.json')),indent=2))
for group in sys.argv[2:]:
 for p,h in checks.items():assert sha(Path(p))==h,p
 start=time.monotonic()
 with (out/(group+'.log')).open('w')as log:
  p=subprocess.Popen([str(out/'Acceptance')],stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,CAD_PROOF_GROUP=group),start_new_session=True)
  try:code=p.wait(timeout=120)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
 (out/(group+'.json')).write_text(json.dumps(dict(exitCode=code,elapsedSeconds=time.monotonic()-start,logSHA256=sha(out/(group+'.log')),premisesSHA256=sha(out/'premises.json')),indent=2));print(group,code,time.monotonic()-start,(out/(group+'.log')).read_text()[-700:],flush=True)
 if code:raise SystemExit(code)
