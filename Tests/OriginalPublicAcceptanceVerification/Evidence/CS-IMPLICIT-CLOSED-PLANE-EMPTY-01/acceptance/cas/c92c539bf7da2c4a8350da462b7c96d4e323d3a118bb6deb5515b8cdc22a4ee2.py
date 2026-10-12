#!/usr/bin/env python3
"""Create an unexecuted, generation-bound Embedded WMO proposal."""
import hashlib, json
from pathlib import Path
R=Path('/private/tmp/cad-m4-m8-completion-20261010')
O=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v1'
def read(p): return json.loads(Path(p).read_text())
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,v): (O/n).write_text(json.dumps(v,indent=2)+'\n')
def binding(p): return dict(path=str(p),sha256=sha(p),bytes=Path(p).stat().st_size)
assert not (O/'profile.json').exists(), 'Preserve the first proposal snapshot'
M=R/'Tests/OriginalDomainConsumerVerification/Evidence/M6/embedded/receipt.json'
D=Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-embedded-production/wasm32-unknown-wasip1/debug')
C=read(D/'description.json')['swiftCommands']['C.CADGeometry-wasm32-unknown-wasip1-debug.module']
V=R/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/value/generation-inventory.json'
E=R/'Tests/OriginalPublicAcceptanceVerification/Evidence/CS-IMPLICIT-CLOSED-PLANE-EMPTY-01/embedded-option-probe/summary.json'
N=R/'.build/cs-implicit-closed-acceptance-native-20261013-v3'
S=R/'.build/cs-implicit-closed-acceptance-native-20261013-v1'
B=R/'.build/cs-implicit-reverse-acceptance-embedded-20261013-v1'
F=R/'.build/cs-implicit-reverse-acceptance-embedded-20261013-v2'
m=read(M); inv=read(V); embedded={Path(k).name:(k,v) for k,v in m['compiler_inputs'].items() if '/CADGeometry/' in k}
assert len(C['sources'])==len(C['objects'])==len(embedded)==len(inv['sourceBindings'])==1651
assert m['swift_sdk']=='swift-6.4.0-RELEASE_wasm-embedded' and C['moduleName']=='CADGeometry'
selected={Path(v['generationInput']).name:v for v in inv['sourceBindings'] if v['primary']}
assert len(selected)==3
(O/'geometry').mkdir(exist_ok=True);(O/'selected').mkdir(exist_ok=True);(O/'source').mkdir(exist_ok=True);(O/'upper').mkdir(exist_ok=True);(O/'fixture').mkdir(exist_ok=True)
sources=[]
for b in inv['sourceBindings']:
 name=Path(b['generationInput']).name; old=Path(b['retainedGenerationInput']); expected=embedded[name][1]
 assert expected==b['generationSHA256']==sha(old)
 p=old
 if name in selected:
  original=R/'Sources/CADGeometry'/('OriginalHigherCurveJets/'+name if name=='OriginalCurveTaylorComposition.swift' else name)
  assert sha(original)==b['compiledSHA256']
  p=O/'selected'/name;p.write_bytes(original.read_bytes())
 sources.append(dict(name=name,generationInput=embedded[name][0],generationSHA256=expected,
  retainedGenerationInput=str(old),compiledInput=str(p),compiledSHA256=sha(p),changedBody=name in selected))
save('geometry-inputs.json',sources)
fl=O/'geometry/inputs.txt';fl.write_text(''.join(b['compiledInput']+'\n' for b in sources))
# Current description is only a flag/inventory carrier; M6 receipt binds old bytes.
args=C['otherArguments']; flags=[];i=0
omit_pairs={'-module-cache-path','-num-threads','-emit-objc-header-path','-j'}
omit_singles={'-serialize-diagnostics','-parseable-output','-emit-objc-header','-whole-module-optimization','-wmo','-j2','-g','-gnone','-Onone'}
while i<len(args):
 if args[i] in omit_pairs:i+=2;continue
 if args[i] in omit_singles:i+=1;continue
 if args[i]=='-Xlinker':i+=2;continue
 flags.append(args[i]);i+=1
flags+=['-Onone','-gnone','-whole-module-optimization','-num-threads','1','-module-cache-path',str(O/'geometry/module-cache'),'-I',str(D/'Modules'),'-module-name','CADGeometry']
frontend=str(Path(C['executable']).with_name('swift-frontend'))
geom_obj=O/'geometry/CADGeometry-WMO.o';geom_mod=O/'geometry/CADGeometry.swiftmodule';wrap=O/'geometry/CADGeometry.swiftmodule.o';archive=O/'geometry/libCADGeometryClosedWMO.a'
commands={
 'geometry-object':[C['executable'],'-c','@'+str(fl),*flags,'-o',str(geom_obj)],
 'geometry-module':[C['executable'],'-emit-module','@'+str(fl),*flags,'-emit-module-path',str(geom_mod)],
 'geometry-modulewrap':[frontend,'-modulewrap',str(geom_mod),'-target','wasm32-unknown-wasip1','-o',str(wrap)],
 'geometry-archive':['/usr/bin/ar','-rcs',str(archive),str(geom_obj),str(wrap)]}
# Derive portable stage flags from an actual accepted reverse Embedded command.
base=read(B/'upper-command.json');portable=base[:base.index('-emit-module')]
for k in ['-module-cache-path']:
 if k in portable:portable[portable.index(k)+1]=str(O/'upper/module-cache')
portable=[portable[0],'-I',str(O/'geometry'),*portable[1:]]
# Four exact source bodies and their admitted qualified prefixes, unchanged.
sr=read(S/'source-compile-receipt.json');assert sr['exitCode']==0
source_bindings=[]
for v in [v for v in sr['command'] if v.endswith('.swift')]:
 p=Path(v);assert sha(p)==sr['checks'][str(p)]
 dest=O/'source'/p.name;dest.write_bytes(p.read_bytes())
 source_bindings.append(dict(priorGenerated=binding(p),generated=binding(dest)))
assert len(source_bindings)==4
source_flags=portable+['-I',str(B/'source')]
source_flags[source_flags.index('-module-cache-path')+1]=str(O/'source/module-cache')
source_archive=O/'source/libImplicitHostPlaneSourcePhase.a'
commands['source4']=source_flags+['-emit-module','-emit-library','-static','-module-name','ImplicitHostPlaneSourcePhase',*[v['generated']['path'] for v in source_bindings],'-emit-module-path',str(O/'source/ImplicitHostPlaneSourcePhase.swiftmodule'),'-o',str(source_archive)]
# Upper body suffixes and qualified owner aliases are copied, not reauthored.
meta=read(N/'upper-premises.json');nc=read(N/'upper-command.json');upper_bindings=[]
for b in meta['bindings']:
 p=Path(b['generated']);assert sha(p)==b['generatedSHA256']
 dest=O/'upper'/p.name;dest.write_bytes(p.read_bytes());upper_bindings.append(dict(prior=b,generated=binding(dest)))
assert len(upper_bindings)==59
selector=Path(next(v for v in nc if v.endswith('/ActualSelectorDeclineAdapters.swift')))
sel=O/'upper'/selector.name;sel.write_bytes(selector.read_bytes())
upper_flags=portable+['-I',str(B/'source'),'-I',str(O/'source')]
upper_archive=O/'upper/libImplicitClosedAcceptanceUpper.a'
commands['upper60']=upper_flags+['-emit-module','-emit-library','-static','-module-name','ImplicitClosedAcceptanceUpper',*[v['generated']['path'] for v in upper_bindings],str(sel),'-emit-module-path',str(O/'upper/ImplicitClosedAcceptanceUpper.swiftmodule'),'-o',str(upper_archive)]
# The fixture remains byte-for-byte frozen within a new import wrapper.
original_proof=Path(next(v for v in nc if v.endswith('/Proof.swift')));fixture=R/'Tests/OriginalPublicAcceptanceVerification/ImplicitClosedPlaneEmptyAcceptance.swift'
old=original_proof.read_bytes();prior_fixture=N/'fixture-at-prepare.swift';assert old.endswith(prior_fixture.read_bytes())
runner=R/'Tests/OriginalPublicAcceptanceVerification/ImplicitReverseDyadicParabolaAcceptance.py'
runner_text=runner.read_text();start=runner_text.index(' return b"""',runner_text.index('def embedded_logging'))+len(' return b"""');end=runner_text.index('"""',start)
portable_logging=runner_text[start:end].encode()
proof=O/'fixture/Proof.swift';proof.write_bytes(old[:-len(prior_fixture.read_bytes())]+portable_logging+b'\n@testable import ImplicitClosedAcceptanceUpper\n'+fixture.read_bytes())
fixture_carrier=read(F/'upper-command.json');archives=[v for v in fixture_carrier if v.endswith('.a')]
old_geometry=[p for p in archives if Path(p).name=='libCachedCADGeometry.a'];assert len(old_geometry)==1
old_upper=[p for p in archives if Path(p).name=='libImplicitAcceptanceUpper.a'];assert len(old_upper)==1
kept=[p for p in archives if p not in old_geometry+old_upper]
assert len(kept)==14
immutable=[]
fr=read(F/'upper-compile-receipt.json');br=read(B/'source-compile-receipt.json');ur=read(B/'upper-module-compile-receipt.json')
expected={}
for receipt in [fr,br,ur]:
 for key in ['checks','inputProducts','products']:
  expected.update(receipt.get(key,{}))
for p in kept:
 assert str(p) in expected and sha(p)==expected[str(p)],p
 immutable.append(binding(p))
# Direct import users plus reused generation nominal modules remain immutable.
for p,h in expected.items():
 if Path(p).suffix in {'.swiftmodule','.swiftdoc','.swiftsourceinfo'} and Path(p).exists():
  assert sha(p)==h,p
  immutable.append(binding(p))
assert (D/'Modules/CADGeometry.swiftmodule').exists()
immutable.append(binding(D/'Modules/CADGeometry.swiftmodule'))
fixture_flags=upper_flags+['-I',str(O/'upper')]
fixture_flags[fixture_flags.index('-module-cache-path')+1]=str(O/'fixture/module-cache')
product=O/'fixture/Acceptance.wasm'
commands['fixture1-link']=fixture_flags+['-emit-executable','-module-name','ImplicitClosedPlaneEmptyAcceptance',str(proof),*kept,str(archive),str(source_archive),str(upper_archive),'-o',str(product)]
node=next(v for v in read(F/'runtime-ordinary-receipt.json')['command'] if Path(v).name=='node')
node_driver=next(v for v in read(F/'runtime-ordinary-receipt.json')['command'] if v.endswith('.mjs'))
commands['runtime-complete']=[node,node_driver,str(product),'complete']
command_bindings={}
for name,c in commands.items():save(name+'-command.json',c);command_bindings[name]=binding(O/(name+'-command.json'))
save('source4-bindings.json',source_bindings);save('upper59-bindings.json',upper_bindings);save('immutable-products.json',immutable)
save('profile.json',dict(state='PROPOSAL-NO-COMPILER-DRIVER-DRYRUN-LINK-RUNTIME',executionCount=0,compilerExecutions=0,driverExecutions=0,dryRuns=0,linkExecutions=0,runtimeExecutions=0,
 receipts=dict(m6Embedded=binding(M),valueInventory=binding(V),optionProbe=binding(E),reverseSource6=binding(B/'source-compile-receipt.json'),reverseUpper=binding(B/'upper-module-compile-receipt.json'),reverseFixture=binding(F/'upper-compile-receipt.json'),nativeClosedUpper=binding(N/'upper-premises.json'),nativeClosedSource4=binding(S/'source-compile-receipt.json')),
 commandCarriers=dict(description=binding(D/'description.json'),reverseUpperCommand=binding(B/'upper-command.json'),reverseFixtureCommand=binding(F/'upper-command.json'),note='Current command/inventory files are not historically receipt-hashed command authority; receipt source and product hashes are checked independently.'),
 toolchain=dict(executable=C['executable'],frontend=frontend,version=m['compiler'],sdk=m['swift_sdk'],target=m['target_triple'],package='nativeexactrelationverification',mode='Embedded',optimization='Onone',wmo=True,geometryCodegenThreads=1),
 counts=dict(geometryDeclarationInputs=1651,changedBodies=3,reusedHistoricalSourceBodies=1648,oldGeometryPartitionObjects=1651,reusedGeometryObjectBodies=0,plannedFreshGeometryCodegenObjects=1,plannedFreshGeometryModuleWrapObjects=1,plannedFreshGeometryModules=1,plannedFreshGeometryArchives=1,freshSourceBodies=4,reusedSource6Bodies=6,freshUpperSelectedBodies=59,upperSelectorBodies=1,fixtureBodies=1,linkedArchives=17,unchangedLinkedArchives=14,lowerCodegen=0,currentMainBroadBuild=0),
 compatibility=dict(sameModule='CADGeometry',samePackage='nativeexactrelationverification',sourceSet='Exact M6 Embedded1651, replacing only the three selected current bodies',storedLayoutChanges='None in the three exact textual diffs; two method-body changes plus one internal instance method addition',freshImportPrecedence=str(O/'geometry'),oldGeometryArchiveRemoved=old_geometry,oldReverseUpperArchiveRemoved=old_upper,source6='Reused immutable ImplicitSourcePhase module/archive. Actual import/link acceptance remains unobserved; no source-at-compile claim is made from matching filenames.',lower='Reused immutable target-matched products; no Core/Kernel/L2-L6 codegen'),
 commands=command_bindings,
 uncertainty=dict(geometryWallSeconds=None,geometryCPUSeconds=None,geometryPeakRSSBytes=None,old919SecondProductIsGeometryTiming=False,commandValidity='Prepared only; no compiler or driver validation',objectCount='Single-object WMO is proposed with num-threads1 and one output; actual production unobserved',portableEntry='Current owner fixture already uses direct if-let getenv decoding. Its current exact bytes replace only the prior fixture suffix in the copied import wrapper; actual Embedded acceptance remains unobserved.'),
 suggestedOperationalBounds=dict(geometry=dict(wallSeconds=1200,perProcessCPUSeconds=1200,ownedCPUSeconds=1200,residentSumBytes=8589934592,scope='Proposed shared aggregate ceilings across the geometry object/module/wrap/archive sequence, not per-command grants or measured requirements; user/root decision pending'),source4=dict(wallSeconds=120,perProcessCPUSeconds=120,ownedCPUSeconds=120),upper60=dict(wallSeconds=240,perProcessCPUSeconds=360,ownedCPUSeconds=360),fixture1=dict(wallSeconds=240,perProcessCPUSeconds=360,ownedCPUSeconds=360),runtimePerGroup=dict(wallSeconds=120,perProcessCPUSeconds=120,ownedCPUSeconds=120),retry='No automatic retry or ceiling increase'),
 fixture=dict(original=binding(fixture),priorProof=binding(original_proof),preparedProof=binding(proof),selector=binding(sel)),
 artifacts=dict(geometryInputs=binding(O/'geometry-inputs.json'),filelist=binding(fl),source4Bindings=binding(O/'source4-bindings.json'),upper59Bindings=binding(O/'upper59-bindings.json'),immutableProducts=binding(O/'immutable-products.json'))))
print(json.dumps(dict(state='PREPARED-NO-EXECUTION',inputs=1651,oldSources=1648,changed3=[(n,b['compiledSHA256']) for n,b in selected.items()],immutableProducts=len(immutable),commands=len(commands),profileSHA256=sha(O/'profile.json'))))
