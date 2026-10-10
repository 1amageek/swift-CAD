#!/usr/bin/env python3
"""Confirm only requested-order review resource/lifetime evidence gaps."""
import argparse,hashlib,json,subprocess,time,uuid
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('lane',choices=['native','asan','wasm','embedded']);args=parser.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1];out=base/'Evidence'/(args.lane+'-lifetime');out.mkdir(exist_ok=False)
scratch=root/'.build/m4-requested-order-lifetime'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
prior=base/'Evidence'/(args.lane+'-accepted')/'receipt.json';r=json.loads(prior.read_text());assert r['success']
checks={}
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def add(path,h=None):
 path=Path(path).resolve();h=h or digest(path);assert digest(path)==h,str(path)
 assert str(path) not in checks or checks[str(path)]==h,str(path)
 checks[str(path)]=h;return path
add(prior);add(__file__);add(base/'LifetimeProof.swift')
for group in ['inputs','product']:
 for n,h in r[group].items():add(n,h)
for n,h in r['logs'].items():add(prior.parent/n,h)
source=add(base/'Proof.swift');original=source.read_text();anchor='@main struct RequestedOrderLiftProof';assert original.count(anchor)==1
fixture=scratch/'RequestedOrderFixture.swift';fixture.write_text(original.replace(anchor,'struct RequestedOrderLiftProof'));add(fixture)
command=next(x['command'] for x in r['runs'] if x['label']=='compile-link').copy();command[command.index(str(source))]=str(fixture)
command.insert(command.index('-o'),str(base/'LifetimeProof.swift'));product=scratch/('LifetimeProof.wasm' if args.lane in ['wasm','embedded'] else 'LifetimeProof');command[command.index('-o')+1]=str(product)
runs=[]
for label,cmd in [('compile-link',command),('proof',[*next(x['command'] for x in r['runs'] if x['label']=='proof')[:-1],str(product)])]:
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:p=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 runs.append({'label':label,'command':cmd,'elapsedSeconds':time.monotonic()-start,'exitCode':p.returncode,'timeoutSeconds':120})
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(label,p.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True);assert p.returncode==0
add(product)
output=(out/'proof.log').read_text()
for marker in ['PASS requested-order pcurve exact work/bytes and terminal cancellation','PASS requested-order detached source/COW and coefficient lifetime']:assert marker in output
for log in out.glob('*.log'):
 assert not any(x in log.read_text() for x in ['warning:','error:','FAIL','data race detected','actor-isolated function','null function','function signature mismatch']),str(log)
for n,h in checks.items():assert digest(n)==h,n
(out/'receipt.json').write_text(json.dumps({'success':True,'lane':args.lane,'scope':'Finding-only actual cached caller against unchanged accepted fresh surface/pcurve objects. Exact added pcurve work/bytes/cancellation and detached source/COW/jet lifetime. No producer rebuild or broad build.','inputs':checks,'product':{str(product):digest(product)},'runs':runs,'logs':{x.name:digest(x) for x in out.glob('*.log')}},separators=(',',':'))+'\n')
