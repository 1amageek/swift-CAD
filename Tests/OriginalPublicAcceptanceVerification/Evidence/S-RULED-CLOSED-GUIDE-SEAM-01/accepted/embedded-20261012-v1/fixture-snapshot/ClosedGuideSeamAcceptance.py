#!/usr/bin/env python3
"""Compile fresh issued-graph/M5/self upper bodies against admitted retained contracts."""
from pathlib import Path
import argparse,ast,hashlib,json,os,re,resource,signal,subprocess,time
p=argparse.ArgumentParser();p.add_argument('lane',nargs='?',choices=['native','asan','wasm','embedded'],default='native');p.add_argument('--output',type=Path,required=True);p.add_argument('--reuse-port',type=Path);p.add_argument('--groups',default='all');args=p.parse_args()
root=Path(__file__).resolve().parents[2];out=args.output.resolve();out.mkdir(exist_ok=False,parents=True)
prior=root/'.build/s-ruled-closed-guide-seam-native-20261012-v2';oldport=root/'.build/cs-draft-zero-ruled-native-20261011-v2'
r=json.loads((prior/'failure-receipt.json').read_text());checks={};fresh=r['freshProduction'].copy();runs=[];historical=r['historicalComparators'].copy();portable=args.lane in {'wasm','embedded'}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,v):(out/n).write_text(json.dumps(v,indent=2)+'\n')
def admit(p,h=None):
 p=Path(p);h=h or sha(p);assert sha(p)==h,str(p);checks[str(p)]=h
def recheck():
 for n,h in checks.items():assert sha(n)==h,n
 for n,h in fresh.items():assert sha(n)==h,n
# Preserve exact cached prechange source comparators instead of calling them current.
for n,h in r['checks'].items():
 path=Path(n)
 if sha(path)==h:admit(path,h);continue
 assert path.parent == root/'Sources/CADGeometry/NativeExactRelations',n
 generated=oldport/'generated'/path.name;source=generated.read_text();body=source[source.index('#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION'):]
 assert hashlib.sha256(body.encode()).hexdigest()==h,n
 target=out/'historical-source'/path.name;target.parent.mkdir(exist_ok=True);target.write_text(body);admit(target,h)
 historical[n]=dict(path=str(target),sha256=h,scope='Original admitted prechange source; current source compiled separately')
admit(prior/'failure-receipt.json');admit(__file__)
fixture=Path(__file__).with_suffix('.swift');admit(fixture)
helpers=[fixture.with_name('LawBoundGuideSeamIdentity.swift'),fixture.with_name('GuideSeamCoonsRegression.swift')]
for helper in helpers:admit(helper)
snapshot=out/'fixture-snapshot';snapshot.mkdir()
for original in [fixture,Path(__file__),*helpers]:
 target=snapshot/original.name;target.write_bytes(original.read_bytes());admit(target)

code=root/'Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamObservation.py';node=next(x for x in ast.parse(code.read_text()).body if isinstance(x,ast.FunctionDef) and x.name=='execute');exec(compile(ast.Module(body=[node],type_ignores=[]),str(code),'exec'))
prefix=(root/'.build/s-ruled-closed-guide-seam-native-20261012-v1/OriginalRuledSurfaceSnapshot.swift').read_text().split('/// The original ruled value',1)[0]
prefix+='\nimport enum RetainedHostAdapters.OriginalDomainAccess\nimport class RetainedHostAdapters.OriginalIdentityReadmission\n'
owner=root/'Sources/CADGeometry/NativeExactRelations'
names=['NativeExactRelationFailure','OriginalIssuedGraphPreparation','OriginalIssuedGraphFamily','OriginalIssuedGraphCompiling','OriginalIssuedGraphFamilyPreparing','DefaultOriginalIssuedGraphCompiler','DefaultOriginalRationalGraphFamilyPreparer','OriginalIssuedGraphRelationResolving','OriginalIssuedGraphRelationOwning','OriginalIssuedGraphRelationPair','OriginalIssuedGraphRelations','OriginalIssuedGraphPredicateEquivalence','OriginalIssuedGraphSolverEquivalence','DefaultOriginalIssuedGraphRelationResolver','OriginalIssuedGraphParameterRefining','OriginalIssuedGraphParameterRefinement','DefaultOriginalIssuedGraphParameterRefiner']
originals=[owner/(n+'.swift') for n in names]
identity=root/'Sources/CADGeometry/OriginalDomainIdentity/OriginalParameterIdentity'
originals += [identity/n for n in ['OriginalRationalSourceBoundaryDeclaration.swift','OriginalLawBoundParameterIdentityIssuing.swift','DefaultOriginalParameterIdentityIssuer+LawBoundBoundary.swift']]
embedding=root/'Sources/CADGeometry/OriginalSurfaceEmbedding'
originals += [embedding/n for n in ['OriginalIssuedGraphSelfContactQuerying.swift','OriginalIssuedGraphSelfContacts.swift','DefaultOriginalIssuedGraphSelfContactQuery.swift','OriginalIssuedGraphSelfIdentityCompiler.swift','OriginalIssuedGraphSelfPredicateSimplifier.swift','OriginalIssuedGraphSelfContactRequestReading.swift','OriginalIssuedDomainCover+SelfContactRequest.swift']]
for path in originals:fresh[str(path)]=sha(path)
module=args.reuse_port.resolve() if args.reuse_port else out
base_flags=json.loads((root/'.build/s-ruled-closed-guide-seam-native-20261012-v1/compile-module.json').read_text())
base_flags=base_flags[:base_flags.index('-emit-library')]
base_proof=json.loads((prior/'compile-proof.json').read_text())
ruled=root/'.build/s-ruled-closed-guide-seam-native-20261012-v1'
if args.lane != 'native':
 # Lane-specific immutable products remain their original nominal owners.
 draft=root/('.build/cs-draft-zero-ruled-'+args.lane+'-20261012-v1')
 def cached(n,h):
  path=Path(n)
  if path.is_file() and sha(path)==h:admit(path,h);return
  if path.is_relative_to(root/'Sources'):
   generated=draft/'generated'/path.name
   if generated.is_file():
    body=generated.read_text();offset=body.find('#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION')
    if offset>=0 and hashlib.sha256(body[offset:].encode()).hexdigest()==h:
     target=out/'historical-source'/path.name;target.parent.mkdir(exist_ok=True);target.write_text(body[offset:]);admit(target,h)
     historical[n]=dict(path=str(target),sha256=h,scope='Unchanged archived body; current upper separately compiled');return
  if path.is_relative_to(root/'Sources'):
   # Recover an exact archived original suffix from its admitted compiled source.
   # This is not an assertion that an unselected archived capability is current.
   first=path.read_text().splitlines()[0]
   for candidate,compiled_hash in globals().get('guide',{}).get('inputs',{}).items():
    archived=Path(candidate)
    if '/.build/' not in candidate or archived.name != path.name:continue
    admit(archived,compiled_hash);body=archived.read_text()
    for match in re.finditer('^'+re.escape(first)+'\\n',body,re.MULTILINE):
     original=body[match.start():]
     if hashlib.sha256(original.encode()).hexdigest()!=h:continue
     target=out/'historical-source'/path.name;target.parent.mkdir(exist_ok=True);target.write_text(original);admit(target,h)
     historical[n]=dict(path=str(target),sha256=h,compiledSource=str(archived),compiledSHA256=compiled_hash,
       scope='Exact archived unselected capability body; no current-body equivalence claim')
     return
  relative=path.relative_to(root)
  assert relative.parts[0] in {'Sources','Tests'},n
  for commit in ['287db282e2e505066228a96db603772fe0cf1d24','9c11fd8d','5cf82ea2','99d61ff1','d963399f','ff67aa6d093ee717cc299573e0687d4263ac5f36']:
   result=subprocess.run(['git','show',commit+':'+str(relative)],cwd=root,capture_output=True,timeout=120)
   if result.returncode==0 and hashlib.sha256(result.stdout).hexdigest()==h:
    target=out/'historical-source'/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(result.stdout);admit(target,h)
    historical[n]=dict(path=str(target),sha256=h,commit=commit);return
  raise AssertionError('Missing lane immutable comparator: '+n)
 draft_receipt=draft/'port-receipt.json';admit(draft_receipt)
 for n,h in json.loads(draft_receipt.read_text())['checks'].items():cached(n,h)
 guide_path=root/'Tests/OriginalGuideCurveRollingBallVerification/Evidence'/args.lane/'receipt.json';admit(guide_path)
 guide=json.loads(guide_path.read_text());assert guide['success']
 for category in ['inputs','product']:
  for n,h in guide[category].items():cached(n,h)
 for n,h in guide['logs'].items():admit(guide_path.parent/n,h)
 guide_command=next(x['command'] for x in guide['runs'] if x['label']=='compile-caller')
 guide_module=Path(guide_command[guide_command.index('-emit-module-path')+1]).parent
 base_flags=json.loads((draft/'compile-port.json').read_text());base_flags=base_flags[:base_flags.index('-emit-library')]+['-I',str(guide_module)]
 base_proof=json.loads((draft/'compile-proof.json').read_text())
 base_proof=base_proof[:base_proof.index('-emit-executable')]+['-I',str(guide_module)]+base_proof[base_proof.index('-emit-executable'):]
 ruled=module/'ruled'
 if not args.reuse_port:ruled.mkdir()
assert 'swift-6.4.0-RELEASE.xctoolchain' in base_flags[0]
for tool in [Path(base_flags[0]),Path(base_flags[0]).with_name('swift-frontend')]:admit(tool)
for i,flag in enumerate(base_flags):
 if flag=='-num-threads':base_flags[i+1]='2'
# All changed-path bodies use one fresh upper nominal port; lower modules are never rebuilt.

try:
 save('admission.json',dict(checks=checks,freshProduction=fresh,historicalComparators=historical,selectedUpperBodies=len(originals),explicitIndependentPreparedQuery=True,lane=args.lane))
 if args.lane != 'native' and not args.reuse_port:
  bodies=[]
  for name in ['OriginalRuledSurfaceSnapshot.swift','OriginalRuledSurfaceSnapshotProvider.swift']:
   original=next((root/'Sources/CADGeometry').rglob(name));fresh[str(original)]=sha(original)
   generated=ruled/name;generated.write_text(prefix+'\n@testable import CallerAdapters\n'+original.read_text());admit(generated);bodies.append(str(generated))
  command=base_flags+['-emit-library','-static','-emit-module','-module-name','RuledObservationAdapters',*bodies,'-emit-module-path',str(ruled/'RuledObservationAdapters.swiftmodule'),'-o',str(ruled/'libRuledObservationAdapters.a')]
  save('compile-ruled.json',command);recheck();execute('compile-ruled',command)
  for name in ['RuledObservationAdapters.swiftmodule','libRuledObservationAdapters.a']:admit(ruled/name)
  save('ruled-receipt.json',dict(state='successful-two-existing-body-compile',checks=checks,freshProduction=fresh,runs=runs));admit(out/'ruled-receipt.json')
  base_flags += ['-I',str(ruled)]
 if args.reuse_port:
  cached=json.loads((module/'port-receipt.json').read_text());assert cached['freshProduction']==fresh
  for n,h in cached['checks'].items():
   if n not in [str(__file__),str(fixture)]:admit(n,h)
  admit(module/'port-receipt.json')
 else:
  generated=[]
  for path in originals:
   target=out/path.name;target.write_text(prefix+path.read_text());admit(target);generated.append(str(target))
  flags=base_flags
  command=flags+['-emit-library','-static','-emit-module','-module-name','GuideSeamPort',*generated,'-emit-module-path',str(out/'GuideSeamPort.swiftmodule'),'-o',str(out/'libGuideSeamPort.a')]
  save('compile-port.json',command);recheck();execute('compile-port',command)
  for name in ['GuideSeamPort.swiftmodule','libGuideSeamPort.a']:admit(out/name)
  save('port-receipt.json',dict(state='successful-fresh-upper-port',checks=checks,freshProduction=fresh,runs=runs));admit(out/'port-receipt.json')
 proof=out/'Proof.swift';proof.write_text(prefix+fixture.read_text()+'\n'+''.join(prefix+helper.read_text()+'\n' for helper in helpers));admit(proof)
 flags=base_proof[:base_proof.index('-emit-executable')]+['-I',str(module),'-I',str(ruled),'-DGUIDE_SEAM_COMBINED_ACCEPTANCE']
 archives=[x for x in base_proof if x.endswith('.a') and not x.endswith('/libDraftZeroRuledPort.a')]
 if args.lane != 'native':archives += [str(guide_module/'libCallerAdapters.a'),str(ruled/'libRuledObservationAdapters.a')]
 archives=list(dict.fromkeys(archives))
 for archive in archives:admit(archive)
 link_flags=[]
 for index in range(base_proof.index('-emit-executable')+1,len(base_proof)):
  if base_proof[index] in {'-Xlinker','-Xclang-linker'}:link_flags += base_proof[index:index+2]
 product=out/('Acceptance.wasm' if portable else 'Acceptance')
 command=flags+link_flags+['-emit-executable',str(proof),str(module/'libGuideSeamPort.a'),*archives,'-o',str(product)]
 save('compile-proof.json',command);recheck();execute('compile-proof',command);admit(product)
 runtime=[str(product)]
 if portable:
  runner=out/'run-group.mjs'
  runner.write_text('import {readFile} from "node:fs/promises";\nimport {WASI} from "node:wasi";\nconst [path,group,work,storage]=process.argv.slice(2);\nconst wasi=new WASI({version:"preview1",args:[path,group],env:{CAD_PROOF_GROUP:group,CAD_QUERY_WORK:work,CAD_QUERY_STORAGE:storage},preopens:{},returnOnExit:true});\nconst module=await WebAssembly.compile(await readFile(path));\nconst instance=await WebAssembly.instantiate(module,wasi.getImportObject());\nconst code=wasi.start(instance);if(code!==0)throw new Error(`WASI exit ${code}`);\n')
  node=Path('/usr/local/bin/node');admit(node);admit(runner);runtime=[str(node),str(runner),str(product)]
 groups=['oracle','graphs','empty','work','storage','cancel','cancel-final','lifetime','identity','coons']
 selected=groups if args.groups=='all' else args.groups.split(',');assert all(x in groups for x in selected)
 work,storage='7068697','212593418'
 save('build-receipt.json',dict(checks=checks,freshProduction=fresh,runs=runs,fixtureSHA256=sha(fixture)))
 for group in selected:
  os.environ['CAD_PROOF_GROUP']=group;os.environ['CAD_QUERY_WORK']=work;os.environ['CAD_QUERY_STORAGE']=storage
  arguments=runtime+[group]+([work,storage] if portable else [])
  log=execute('runtime-'+group,arguments)
  if group=='oracle':
   work=re.search(r'QUERY_WORK: ([0-9]+)',log).group(1);storage=re.search(r'QUERY_STORAGE: ([0-9]+)',log).group(1)
  recheck();print(log,flush=True)
 save('receipt.json',dict(success=True,cellComplete=False,lane=args.lane,groups=selected,checks=checks,freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True,queryWork=int(work),queryStorage=int(storage),scope='Current selected27 upper bodies; actual retained source/DI and L2-L6 products reused; explicit independent raw/prepared operations and verification-only oracle admissions.'))
 print('RECEIPT',sha(out/'receipt.json'))
except BaseException:
 recheck();save('failure-receipt.json',dict(success=False,cellComplete=False,checks=checks,freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True));raise
