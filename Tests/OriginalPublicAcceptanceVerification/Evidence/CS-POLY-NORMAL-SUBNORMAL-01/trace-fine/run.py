from pathlib import Path
import json,subprocess,time,os,signal
out=Path(__file__).parent
for name in ['port','proof']:
 c=json.loads((out/(name+'-command.json')).read_text());start=time.monotonic()
 with (out/(name+'-compile.log')).open('w') as log:
  p=subprocess.Popen(c,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  try: code=p.wait(timeout=120)
  except subprocess.TimeoutExpired: os.killpg(p.pid,signal.SIGTERM);p.wait();raise
 print(name,code,round(time.monotonic()-start,3),flush=True)
 if code: print((out/(name+'-compile.log')).read_text()[:12000]);raise SystemExit(code)
c=[str(out/'proof'),'scaled-normals'];start=time.monotonic()
with (out/'runtime.log').open('w') as log:
 p=subprocess.Popen(c,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 try: code=p.wait(timeout=120)
 except subprocess.TimeoutExpired: os.killpg(p.pid,signal.SIGTERM);p.wait();raise
print((out/'runtime.log').read_text());print('runtime',code,round(time.monotonic()-start,3))
