from pathlib import Path
import json,hashlib,subprocess,time,os,signal
p=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for f,h in json.loads((p/'premises.json').read_text()).items():assert sha(f)==h,f
command=json.loads((p/'command.json').read_text());start=time.monotonic()
with (p/'compile.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=120)
assert r.returncode==0
with (p/'runtime.log').open('w')as log:
 process=subprocess.Popen([str(p/'Acceptance')],stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,CAD_PROOF_GROUP='broad-box-cause'),start_new_session=True)
 try:code=process.wait(timeout=120)
 except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait();code=124
(p/'receipt.json').write_text(json.dumps(dict(exitCode=code,elapsedSeconds=time.monotonic()-start,fixtureSHA256=sha(p/'fixture.swift'),executableSHA256=sha(p/'Acceptance'),premisesSHA256=sha(p/'premises.json'),logSHA256=sha(p/'runtime.log'),classification='diagnostic only, not accepted success'),indent=2))
print((p/'runtime.log').read_text(),flush=True)
