from pathlib import Path
import argparse,hashlib,importlib.util,json,re
R=Path('/private/tmp/cad-m4-m8-completion-20261010');B=R/'.build/cs-implicit-closed-wasm-prepared-20261013-v1';O=R/'.build/cs-implicit-closed-wasm-prepared-20261013-v2';T=R/'Tests/OriginalPublicAcceptanceVerification'
def read(p):return json.loads(Path(p).read_text())
def save(p,v):Path(p).write_text(json.dumps(v,indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def add(d,p,h=None):
 p=Path(p);actual=sha(p);assert h is None or h==actual;d[str(p)]=actual
parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['prepare','archive','upper','runtime']);parser.add_argument('--groups');args=parser.parse_args();O.mkdir(exist_ok=True)
spec=importlib.util.spec_from_file_location('closed_wasm_actual_bounded',T/'ImplicitReverseDyadicParabolaAcceptance.py');helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper);helper.OUT=O
if args.stage=='prepare':
 assert not (O/'archive-started.json').exists();old=read(B/'execution-premises.json');periodic=R/'Tests/OriginalPeriodicLiftVerification/Evidence/actual-wasm/runs.json';ar=next(x for x in read(periodic)if x['label']=='archive-CADGeometry')['command'];archive=read(B/'archive-command.json');assert archive[0]=='/usr/bin/ar';archive[0]=ar[0];archive[1]=ar[1];archive[2]=str(O/'libCachedCADGeometrySelected3.a');assert archive[3:]==read(B/'archive-command.json')[3:];save(O/'archive-command.json',archive)
 upper=read(B/'upper-command.json');upper[upper.index(str(B/'libCachedCADGeometrySelected3.a'))]=archive[2];upper[upper.index('-module-cache-path')+1]=str(O/'upper-module-cache');upper[upper.index('-o')+1]=str(O/'Acceptance');save(O/'upper-command.json',upper)
 checks={name:dict(old[name])for name in ['archiveChecks','upperChecks']}
 for values in checks.values():
  for p in [Path(__file__).resolve(),periodic,Path(ar[0]),B/'upper-compile-receipt.json',B/'upper-compile.log',B/'archive-receipt.json',B/'archive.log',O/'archive-command.json',O/'upper-command.json']:add(values,p)
 text=(B/'upper-compile.log').read_text();m=re.search(r'(/var/[^ :]+/TemporaryDirectory\.[^/]+/[^ :]+\.o)',text);temporary=Path(m.group(1));assert not temporary.exists()and not temporary.parent.exists()
 save(O/'repair-premises.json',dict(driverSHA256=sha(__file__),**checks,originalProfile=str(B/'profile.json'),originalExecutionPremises=str(B/'execution-premises.json'),freshPrimaryReceipt=str(B/'primary3-receipt.json'),sourceModuleReceipt=str(B/'source-compile-receipt.json'),correctTool=dict(path=ar[0],sha256=sha(ar[0]),authority=dict(path=str(periodic),sha256=sha(periodic))),archivedObjectCount=len(archive[3:]),objectsExactEqual=True,onlyArchiveCommandChanges='Mac ar→original receipt-bound llvm-ar/-rcs and private output path; all1652object inputs identical.',upperAssembly='same61 actual Swift inputs compile/link once because failed driver removed all temporary frontend objects',temporaryObject=dict(path=str(temporary),exists=False,parentExists=False),source6Codegen=0,lowerCodegen=0,primary3Codegen=0,source4Codegen=0,publicCapsUnchanged=True))
 (O/'driver-at-prepare.py').write_bytes(Path(__file__).read_bytes());print('PREPARED CAUSAL WASM V2',sha(O/'repair-premises.json'),flush=True)
else:
 meta=read(O/'repair-premises.json');assert meta['driverSHA256']==sha(__file__);checks=dict(meta['archiveChecks']if args.stage=='archive'else meta['upperChecks']);add(checks,O/'repair-premises.json');snap=O/('driver-at-'+args.stage+'.py');snap.write_bytes(Path(__file__).read_bytes());add(checks,snap)
 primary=read(B/'primary3-receipt.json');assert primary['exitCode']==0;products=dict(primary['products']);add(checks,B/'primary3-receipt.json')
 if args.stage in ['upper','runtime']:
  for receipt in [O/'archive-receipt.json',B/'source-compile-receipt.json']:
   raw=read(receipt);assert raw['exitCode']==0;products.update(raw['products']);add(checks,receipt)
 if args.stage=='runtime':
  raw=read(O/'upper-compile-receipt.json');assert raw['exitCode']==0;products.update(raw['products']);add(checks,O/'upper-compile-receipt.json');node=Path('/usr/local/bin/node');wasi=B/'run.mjs'
  if not wasi.exists():wasi.write_text('import {readFile} from "node:fs/promises";\nimport {WASI} from "node:wasi";\nconst [path,group]=process.argv.slice(2);\nconst wasi=new WASI({version:"preview1",args:[path,group],env:{CAD_PROOF_GROUP:group},preopens:{},returnOnExit:true});\nconst module=await WebAssembly.compile(await readFile(path));\nconst instance=await WebAssembly.instantiate(module,wasi.getImportObject());\nconst code=wasi.start(instance);if(code!==0)throw new Error(`WASI exit ${code}`);\n')
  add(checks,node);add(checks,wasi)
  for group in args.groups.split(','):
   result=helper.bounded('runtime-'+group,[str(node),str(wasi),str(O/'Acceptance'),group],checks,products);assert result['exitCode']==0,'Actual group stop: '+group
 else:
  label='archive'if args.stage=='archive'else'upper-compile';result=helper.bounded(label,read(O/('archive-command.json'if args.stage=='archive'else'upper-command.json')),checks,products)
  if result['exitCode']==0:
   product=O/('libCachedCADGeometrySelected3.a'if args.stage=='archive'else'Acceptance');result['products']={str(product):sha(product)};save(O/(label+'-receipt.json'),result)
  assert result['exitCode']==0,'Actual assembly stop: '+args.stage
