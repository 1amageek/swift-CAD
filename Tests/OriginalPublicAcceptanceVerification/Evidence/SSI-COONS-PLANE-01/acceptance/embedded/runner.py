"""Compile and execute the ordinary SSI fixture against receipt-admitted full lane products."""
from pathlib import Path
import hashlib,json,os,signal,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.build/coons-ssi-recovery-20261012'
SWIFTC=Path('/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc')
FIXTURE=Path(__file__).with_name('CoonsPlaneSSIAcceptance.swift')
WASI=Path(__file__).with_name('CoonsPlaneSSIWASI.mjs')
GROUPS=['success','requests','empty']+['bare-'+str(i)+'-'+side for i in range(3) for side in ['forward','reverse']]+['bare-empty','resources','depth','cancel','lifetime']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
def bounded(command,log,env,seconds):
 start=time.monotonic()
 with log.open('w')as stream:
  process=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  try:code=process.wait(timeout=seconds)
  except subprocess.TimeoutExpired:
   os.killpg(process.pid,signal.SIGKILL);process.wait();code=124
 return dict(command=command,exitCode=code,elapsedSeconds=time.monotonic()-start,
  wallLimitSeconds=seconds,logSHA256=sha(log))
def main():
 lane=sys.argv[1];version=sys.argv[2]if len(sys.argv)>2 else 'public';out=BASE/(lane+'-'+version);out.mkdir(exist_ok=False)
 receipt_path=BASE/lane/'receipt.json';receipt=json.loads(receipt_path.read_text())
 assert receipt['exitCode']==0 and receipt['sourcePostHashesMatch']
 for p,digest in receipt['inputs'].items():assert sha(ROOT/p)==digest,p
 for p,digest in receipt['products'].items():assert sha(BASE/lane/p)==digest,p
 (out/'fixture.swift').write_bytes(FIXTURE.read_bytes());(out/'runner.py').write_bytes(Path(__file__).read_bytes())
 flags=['-parse-as-library','-swift-version','6','-Onone','-enable-testing']
 if lane=='asan':
  products=BASE/lane/'build/out/Products/Debug'
  sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
  flags+=['-sdk',sdk,'-target','arm64-apple-macosx15.0','-sanitize=address']
  objects=[products/(n+'.o')for n in ['CADGeometry','CADCore','HashTreeCollections','InternalCollectionsUtilities']]
 else:
  products=BASE/lane/'build/out/Products/Debug-webassembly-wasm32'
  sdk_id='swift-6.4.0-RELEASE_'+('wasm-embedded'if lane=='embedded'else'wasm')
  config=subprocess.check_output([str(SWIFTC.with_name('swift')),'sdk','configure','--show-configuration',sdk_id],text=True)
  (out/'sdk-configuration.txt').write_text(config)
  values=dict(line.split(': ',1)for line in config.splitlines()if ': 'in line)
  flags+=['-target','wasm32-unknown-wasip1','-sdk',values['sdkRootPath'],
   '-resource-dir',values['swiftResourcesPath'],'-static-stdlib',
   '-Xlinker','-z','-Xlinker','stack-size=67108864',
   '-Xclang-linker','-resource-dir','-Xclang-linker',str(Path(values['swiftResourcesPath'])/'clang')]
  if lane=='embedded':flags+=['-enable-experimental-feature','Embedded','-wmo',
   '-L',str(Path(values['swiftStaticResourcesPath'])/'wasip1'),'-Xlinker','-lc++','-Xlinker','-lswift_Concurrency','-Xlinker','-lswiftUnicodeDataTables']
  objects=sorted(p for name in ['CADGeometry','CADCore','HashTreeCollections','InternalCollectionsUtilities']
   for p in (products/(name+'.objlib')).rglob('*.o'))
  assert len(objects)>2000
 flags+=['-I',str(products)]
 rsp=out/'objects.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n')
 checks={str(p):sha(p)for p in objects}
 for name in ['CADGeometry','CADCore','HashTreeCollections','InternalCollectionsUtilities']:
  for p in (products/(name+'.swiftmodule')).rglob('*.swiftmodule'):checks[str(p)]=sha(p)
 checks[str(receipt_path)]=sha(receipt_path);checks[str(out/'fixture.swift')]=sha(out/'fixture.swift')
 checks[str(out/'runner.py')]=sha(out/'runner.py');checks[str(WASI)]=sha(WASI)
 save(out/'premises.json',dict(inputs=receipt['inputs'],checks=checks,sourceCount=len(receipt['inputs']),toolchain=receipt['toolchain'],sdk=receipt['sdkIdentifier']))
 executable=out/('Acceptance'if lane=='asan'else'Acceptance.wasm')
 command=[str(SWIFTC),*flags,str(FIXTURE),'@'+str(rsp),'-o',str(executable)]
 compile_result=bounded(command,out/'compile.log',os.environ.copy(),120)
 compile_result.update(fixtureSHA256=sha(FIXTURE),premisesSHA256=sha(out/'premises.json'))
 if executable.exists():compile_result['executableSHA256']=sha(executable)
 save(out/'compile.json',compile_result);print(lane,'compile',compile_result['exitCode'],flush=True)
 if compile_result['exitCode']:raise SystemExit(compile_result['exitCode'])
 for group in GROUPS:
  assert sha(executable)==compile_result['executableSHA256'] and sha(FIXTURE)==compile_result['fixtureSHA256']
  env=dict(os.environ,CAD_PROOF_GROUP=group)
  command=[str(executable)]if lane=='asan'else['/usr/local/bin/node',str(WASI),str(executable)]
  result=bounded(command,out/(group+'.log'),env,120)
  result.update(executableSHA256=sha(executable),fixtureSHA256=sha(FIXTURE),compileReceiptSHA256=sha(out/'compile.json'))
  save(out/(group+'.json'),result);print(lane,group,result['exitCode'],round(result['elapsedSeconds'],3),flush=True)
  if result['exitCode']:raise SystemExit(result['exitCode'])
 for p,digest in checks.items():assert sha(p)==digest,p
 for p,digest in receipt['inputs'].items():assert sha(ROOT/p)==digest,p
 save(out/'summary.json',dict(status='PASS',groups=GROUPS,fixtureSHA256=sha(FIXTURE),compileReceiptSHA256=sha(out/'compile.json'),premisesSHA256=sha(out/'premises.json'),postPremisesMatch=True))
if __name__=='__main__':main()
