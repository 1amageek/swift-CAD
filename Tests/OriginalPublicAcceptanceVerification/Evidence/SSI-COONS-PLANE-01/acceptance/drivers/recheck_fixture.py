from pathlib import Path
import subprocess,json,hashlib,time,os,signal,sys
root=Path.cwd();out=root/'.build/coons-ssi-recovery-20261012/native-public';version=sys.argv[1];groups=sys.argv[2:];target=out/version;target.mkdir(exist_ok=False);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
old=json.loads((out/'linked-products.json').read_text());fixture=root/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIAcceptance.swift'
for p,h in old.items():
 if p not in [str(fixture),str(out/'Acceptance')]:assert sha(Path(p))==h,p
command=json.loads((out/'fixture-compile.json').read_text())['command'];command[-1]=str(target/'Acceptance')
(target/'fixture.swift').write_bytes(fixture.read_bytes());(target/'command.json').write_text(json.dumps(command,indent=2));start=time.monotonic()
with (target/'compile.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=120)
print('COMPILE',r.returncode,flush=True)
if r.returncode:raise SystemExit(r.returncode)
products={p:h for p,h in old.items()if p not in [str(fixture),str(out/'Acceptance')]};products[str(target/'Acceptance')]=sha(target/'Acceptance');products[str(target/'fixture.swift')]=sha(target/'fixture.swift')
(target/'receipt.json').write_text(json.dumps(dict(exitCode=0,elapsedSeconds=time.monotonic()-start,command=command,products=products,logSHA256=sha(target/'compile.log')),indent=2))
for group in groups:
 for p,h in products.items():assert sha(Path(p))==h,p
 env=dict(os.environ,CAD_PROOF_GROUP=group);start=time.monotonic()
 with (target/(group+'.log')).open('w')as log:
  p=subprocess.Popen([str(target/'Acceptance')],stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  try:code=p.wait(timeout=120)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
 meta=dict(exitCode=code,elapsedSeconds=time.monotonic()-start,receiptSHA256=sha(target/'receipt.json'),logSHA256=sha(target/(group+'.log')))
 (target/(group+'.json')).write_text(json.dumps(meta,indent=2));print(group,code,meta['elapsedSeconds'],flush=True)
 if code:raise SystemExit(code)
