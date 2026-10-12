from pathlib import Path
import argparse,hashlib,importlib.util,json,os
R=Path('/private/tmp/cad-m4-m8-completion-20261010');T=R/'Tests/OriginalPublicAcceptanceVerification';REV=T/'Evidence/CS-IMPLICIT-REVERSE-DYADIC-PARABOLA-ON-HOST-01/acceptance';N=R/'.build/cs-implicit-closed-acceptance-native-20261013-v4';B=R/'.build/cs-implicit-closed-value-native-20261013-v2'
def read(p):return json.loads(Path(p).read_text())
def save(p,v):Path(p).write_text(json.dumps(v,indent=2)+'\n')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def add(d,p,h=None):
 p=Path(p);actual=sha(p);assert h is None or h==actual,'Changed input: '+str(p);d[str(p)]=actual
parser=argparse.ArgumentParser();parser.add_argument('lane',choices=['asan','wasm']);parser.add_argument('--stage',choices=['prepare','primary','archive','source','upper','runtime'],required=True);parser.add_argument('--groups');args=parser.parse_args();O=R/f'.build/cs-implicit-closed-{args.lane}-prepared-20261013-v1';profile=read(O/'profile.json')
spec=importlib.util.spec_from_file_location('closed_actual_bounded',T/'ImplicitReverseDyadicParabolaAcceptance.py');helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper);helper.OUT=O
if args.stage=='prepare':
 assert not (O/'primary3-started.json').exists()
 manifest=read(REV/'manifest.json');archived={(v.get('originalPath',k.split('#')[0]),v['sha256']):R/v['path']for k,v in manifest['files'].items()};historical=[];base={};summary=read(REV/'summary.json');part=next(x for x in summary['accepted']if x['lane']==args.lane)
 for ref in [part['receipt'],part['sourceModuleReceipt']]:
  add(base,R/ref['path'],ref['sha256']);raw=read(R/ref['path'])
  for p,h in {**raw['checks'],**raw.get('products',{})}.items():
   if Path(p).exists() and sha(p)==h:base[p]=h
   else:
    q=archived.get((p,h));assert q is not None,'Missing immutable prior: '+p+'#'+h;add(base,q,h);historical.append(dict(originalPath=p,sha256=h,retainedPath=str(q)))
 for p in [REV/'summary.json',REV/'manifest.json',Path(__file__).resolve(),T/'ImplicitReverseDyadicParabolaAcceptance.py',O/'profile.json']:add(base,p)
 driver=O/'driver-at-prepare.py';driver.write_bytes(Path(__file__).read_bytes());add(base,driver)
 primary=dict(base);inventory=read(B/'generation-inventory.json');add(primary,B/'generation-inventory.json');add(primary,profile['originalGenerationReceipt']['path'],profile['originalGenerationReceipt']['sha256'])
 for s in inventory['sourceBindings']:add(primary,s['compiledInput'],s['compiledSHA256'])
 add(primary,B/'generation-filelist-with-selected3.txt');add(primary,O/'primary3-command.json')
 primaryCmd=read(O/'primary3-command.json');primaryOutputs=[primaryCmd[i+1]for i,x in enumerate(primaryCmd)if x=='-o'];assert len(primaryOutputs)==3
 archive=dict(base);add(archive,O/'archive-command.json');generation=read(profile['originalGenerationReceipt']['path']);objects=read(O/'archive-command.json')[3:];genBase=Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-'+('native'if args.lane=='asan'else'wasm')+'-production')
 for p in objects:
  if p in primaryOutputs:continue
  key=str(Path(p).relative_to(genBase));add(archive,p,generation['products'][key])
 source=dict(base);add(source,O/'source4-command.json')
 sourceMeta=read(R/'.build/cs-implicit-closed-acceptance-native-20261013-v1/source-premises.json')
 for b in sourceMeta['bindings']:add(source,b['original'],b['originalSHA256']);add(source,b['generated'],b['generatedSHA256'])
 upper=dict(base);native=read(N/'upper-premises.json')
 for b in native['bindings']:add(upper,b['original'],b['originalSHA256']);add(upper,b['generated'],b['generatedSHA256'])
 for p in [N/'Proof.swift',O/'upper-command.json',T/'ImplicitClosedPlaneEmptyAcceptance.swift']:add(upper,p)
 upperCmd=read(O/'upper-command.json')
 for p in upperCmd:
  if p.endswith('.a')and p not in [str(O/'libCachedCADGeometrySelected3.a'),str(O/'source/libImplicitHostPlaneSourcePhase.a')]:add(upper,p)
 selector=next(p for p in upperCmd if Path(p).name=='ActualSelectorDeclineAdapters.swift');add(upper,selector)
 save(O/'execution-premises.json',dict(driverSHA256=sha(__file__),primaryChecks=primary,archiveChecks=archive,sourceChecks=source,upperChecks=upper,primaryOutputs=primaryOutputs,historicalBindings=historical,source6Codegen=0,lowerCodegen=0,selected3ASANScope='Only changed3 primaries and fresh source4/upper/fixture are instrumented; retained cached generation/lower artifacts preserve their original accepted instrumentation scope.' if args.lane=='asan'else None))
 print(json.dumps(dict(state='EXECUTION-PREPARED',lane=args.lane,premisesSHA256=sha(O/'execution-premises.json'),checks={k:len(v)for k,v in [('primary',primary),('archive',archive),('source',source),('upper',upper)]})),flush=True)
else:
 meta=read(O/'execution-premises.json');assert sha(__file__)==meta['driverSHA256'];stage=args.stage;checks=dict(meta[{'primary':'primaryChecks','archive':'archiveChecks','source':'sourceChecks','upper':'upperChecks','runtime':'upperChecks'}[stage]])
 add(checks,O/'execution-premises.json');snap=O/('driver-at-'+stage+'.py');snap.write_bytes(Path(__file__).read_bytes());add(checks,snap);products={}
 if stage in ['archive','upper','runtime']:
  primary=read(O/'primary3-receipt.json');assert primary['exitCode']==0;products.update(primary['products']);add(checks,O/'primary3-receipt.json')
 if stage in ['upper','runtime']:
  for name in ['archive','source-compile']:
   raw=read(O/(name+'-receipt.json'));assert raw['exitCode']==0;products.update(raw['products']);add(checks,O/(name+'-receipt.json'))
 if stage=='runtime':
  upper=read(O/'upper-compile-receipt.json');assert upper['exitCode']==0;add(checks,O/'upper-compile-receipt.json');products.update(upper['products']);command=[str(O/'Acceptance')]
  os.environ.pop('CAD_PROOF_REUSE_NATIVE_CONTROLS',None)
  if args.lane=='wasm':
   wasi=O/'run.mjs';wasi.write_text('import {readFile} from "node:fs/promises";\nimport {WASI} from "node:wasi";\nconst [path,group]=process.argv.slice(2);\nconst wasi=new WASI({version:"preview1",args:[path,group],env:{CAD_PROOF_GROUP:group},preopens:{},returnOnExit:true});\nconst module=await WebAssembly.compile(await readFile(path));\nconst instance=await WebAssembly.instantiate(module,wasi.getImportObject());\nconst code=wasi.start(instance);if(code!==0)throw new Error(`WASI exit ${code}`);\n');add(checks,wasi);node=Path('/usr/local/bin/node');add(checks,node);command=[str(node),str(wasi),str(O/'Acceptance')]
  for group in args.groups.split(','):
   raw=helper.bounded('runtime-'+group,command+[group],checks,products);assert raw['exitCode']==0,'Actual stop: '+group
 else:
  label={'primary':'primary3','archive':'archive','source':'source-compile','upper':'upper-compile'}[stage];file={'primary':'primary3','archive':'archive','source':'source4','upper':'upper'}[stage];raw=helper.bounded(label,read(O/(file+'-command.json')),checks,products)
  if raw['exitCode']==0:
   outputs=meta['primaryOutputs']if stage=='primary'else [str(O/'libCachedCADGeometrySelected3.a')]if stage=='archive'else [str(p)for p in (O/'source').iterdir()if p.suffix in ['.swiftmodule','.swiftdoc','.swiftsourceinfo','.a']]if stage=='source'else [str(O/'Acceptance')]
   raw['products']={p:sha(p)for p in outputs};save(O/(label+'-receipt.json'),raw)
  assert raw['exitCode']==0,'Actual compile stage stop: '+stage
