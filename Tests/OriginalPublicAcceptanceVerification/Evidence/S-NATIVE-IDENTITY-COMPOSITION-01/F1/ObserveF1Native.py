from pathlib import Path
import hashlib,json,os,resource,signal,subprocess,time,shlex,re
root=Path.cwd()
out=root/'.build/s-native-identity-composition-f1-native-20261013-v1'
out.mkdir(exist_ok=False)
checks,fresh,products,runs,historical={},{},{},[],{}
# Reuse only the bounded process owner, not the old assembly or its evidence decisions.
runner=(root/'.build/s-native-identity-composition-prototype-20261013-v2/NativeIdentityCompositionAcceptance.py').read_text()
exec(runner[runner.index('def sha(path):'):runner.index('# Exact archived text comparators')])
packet=root/'Tests/OriginalPublicAcceptanceVerification/Evidence/S-NATIVE-IDENTITY-COMPOSITION-01'
manifest=read(packet/'manifest.json')
origins={(x['originalPath'],x['sha256']):root/x['retained']['path']for x in manifest['originTuples']}
previous=root/'.build/s-native-identity-composition-native-controls-20261013-v3'
prior=read(previous/'receipt.json')
admit(previous/'receipt.json','1aa24fd3bb4ecfd85e95421864600adca4c5c4aba3aa96d1b91f25357eb1e90a')
for n,d in prior['checks'].items():
 p=Path(n)
 if p.is_file()and sha(p)==d:admit(p,d)
 else:
  p=origins[(n,d)];admit(p,d);historical[n]=dict(path=str(p),sha256=d)
for n,d in prior['products'].items():admit(n,d)
for n,d in prior['selectedProduction'].items():admit(n,d)
fixture=root/'Tests/OriginalPublicAcceptanceVerification/NativeIdentityCompositionAcceptance.swift'
admit(fixture,'a97ee6c0cb20c8e5c54f8b2945bcaee32eb005757d22036fccf9e02c1880a7fe')
admit(Path(__file__).resolve(),sha(Path(__file__).resolve()))
(out/Path(__file__).name).write_bytes(Path(__file__).read_bytes())
oldlink=read(previous/'compile-link.json')
oldissuer=next(x for x in oldlink if x.endswith('/DI.build/DefaultOriginalParameterIdentityIssuer.swift.o'))
oldbase=Path(oldissuer).parents[4]
description=oldbase/'build/arm64-apple-macosx/debug/description.json'
yaml=oldbase/'build/debug.yaml'
admit(description,sha(description));admit(yaml,'32bc97549615e1ed01518938b9ce0f95088688251927b2c960066e6c77905e27')
v=next(x for x in read(description)['swiftCommands'].values()if x['moduleName']=='DI')
assert len(v['sources'])==105 and not v['wholeModuleOptimization']
for n in v['objects']:admit(n,sha(n))
admit(v['moduleOutputPath'],sha(v['moduleOutputPath']))
for name in ['DI.swiftdoc','DI.swiftsourceinfo']:
 p=Path(v['moduleOutputPath']).with_name(name)
 if p.is_file():admit(p,sha(p))
lookup={p.name:p for p in (root/'Sources/CADGeometry/OriginalDomainIdentity').rglob('*.swift')}
snapshots=[];inputbindings=[]
for n in v['sources']:
 old=Path(n);current=lookup[old.name]
 assert old.read_bytes()==current.read_bytes()
 rel=old.relative_to(oldbase/'package/Sources/DI');target=out/'DI-inputs'/rel
 target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(current.read_bytes())
 for p in [old,current,target]:admit(p,sha(p))
 snapshots.append(str(target))
 inputbindings.append(dict(originalPath=str(current),cachedInputPath=str(old),snapshotPath=str(target),sha256=sha(target),bytes=target.stat().st_size))
issuer=next(n for n in snapshots if n.endswith('/DefaultOriginalParameterIdentityIssuer.swift'))
assert sha(issuer)=='71589c394b50fd0d564e0639e65c96e22bed5345fcd36146be4137713ec70efa'
flags=[];i=0
skipPairs={'-index-store-path','-module-cache-path','-emit-objc-header-path'}
skipSingle={'-incremental','-enable-batch-mode','-serialize-diagnostics','-parseable-output','-emit-objc-header','-j2'}
while i<len(v['otherArguments']):
 x=v['otherArguments'][i]
 if x in skipPairs:i+=2;continue
 if x in skipSingle:i+=1;continue
 flags.append(x);i+=1
flags+=['-module-cache-path',str(out/'module-cache'),'-I',v['importPath']]
compiler=v['executable'];assert 'swift-6.4.0-RELEASE.xctoolchain'in compiler
for p in [compiler,str(Path(compiler).with_name('swift-frontend'))]:admit(p,sha(p))
module= [compiler,'-emit-module','-module-name','DI','-emit-module-path',str(out/'DI.swiftmodule'),*flags,*snapshots]
save('compile-di-module-only.json',module)
save('source-bindings105.json',inputbindings)
def finish(state,success):
 save('receipt.json'if success else'failure-receipt.json',dict(cell='S-NATIVE-IDENTITY-COMPOSITION-01',finding='F1',lane='native',state=state,success=success,
  freshDIModuleInputs=105,freshPrimaryBodies=1,reusedOtherDIObjects=104,rebuiltLowerBodies=0,
  sourceBindings=inputbindings,oldIssuerObject=oldissuer,checks=checks,products=products,runs=runs,historicalComparators=historical,
  scope='Fresh current DI module-only and issuer primary1; same module/package/inputs/API/layout; one old issuer object replaced in immutable caller linklist. Native finding-only source binding and public behavior; other lanes unobserved.'))
recheck()
code=execute('compile-di-module-only',module)
if code:finish('module-only-compile-stop',False);raise SystemExit(code)
for p in out.glob('DI.swift*'):products[str(p)]=sha(p)
# Ask the existing driver to describe one-primary jobs, then execute only the issuer job.
outputmap={n:{'object':str(out/'unexecuted-objects'/(Path(n).name+'.o'))}for n in snapshots}
outputmap[issuer]['object']=str(out/'CurrentOriginalParameterIdentityIssuer.o')
save('primary-output-file-map.json',outputmap)
describe=[compiler,'-c','-module-name','DI','-disable-batch-mode','-output-file-map',str(out/'primary-output-file-map.json'),*flags,*snapshots,'-driver-print-jobs']
save('describe-primary-jobs.json',describe)
code=execute('describe-primary-jobs',describe)
if code:finish('primary-job-description-stop',False);raise SystemExit(code)
jobs=[shlex.split(line)for line in (out/'describe-primary-jobs.log').read_text().splitlines()if '-frontend' in line and '-primary-file' in line]
job=next(x for x in jobs if any(x[i]=='-primary-file'and x[i+1]==issuer for i in range(len(x)-1)))
assert job.count('-primary-file')==1 and job[job.index('-o')+1]==str(out/'CurrentOriginalParameterIdentityIssuer.o')
save('compile-current-primary1.json',job)
recheck();code=execute('compile-current-primary1',job)
if code:finish('primary1-compile-stop',False);raise SystemExit(code)
newobject=out/'CurrentOriginalParameterIdentityIssuer.o';products[str(newobject)]=sha(newobject)
# Check actual symbol definitions before replacing exactly one original link input.
nm=str(Path(compiler).with_name('llvm-nm'))
for label,p in [('old',Path(oldissuer)),('fresh',newobject)]:
 command=[nm,'--defined-only',str(p)];save('symbols-'+label+'.json',command)
 code=execute('symbols-'+label,command)
 if code:finish('symbol-read-stop',False);raise SystemExit(code)
 text=(out/('symbols-'+label+'.log')).read_text()
 assert all(re.search('DefaultOriginalParameterIdentityIssuer.*'+name,text)for name in ['restricted','symmetric','compose'])
link=oldlink.copy();assert link.count(oldissuer)==1
link[link.index(oldissuer)]=str(newobject)
oldfixture=next(x for x in link if x.endswith('/NativeIdentityCompositionAcceptance.swift'))
link[link.index(oldfixture)]=str(fixture)
link[1:1]=['-I',str(out)]
link[link.index('-o')+1]=str(out/'CompositionF1')
save('compile-link-fresh-import.json',link)
recheck();code=execute('compile-link-fresh-import',link)
if code:finish('fresh-import-link-stop',False);raise SystemExit(code)
products[str(out/'CompositionF1')]=sha(out/'CompositionF1')
save('ready-to-run-complete.json',dict(checks=checks,products=products,runs=runs))
costs=None
for group in ['complete','controls','exact','work','storage','cancel']:
 arg=group if group in ['complete','controls']else group+':'+':'.join(str(x)for x in costs)
 recheck();code=execute('runtime-'+group,[str(out/'CompositionF1'),arg]);recheck()
 if code:finish('observed-'+group+'-stop',False);raise SystemExit(code)
 if group=='controls':
  matches=re.findall(r'METRIC preparedQueryBoundary (\d+) (\d+) (\d+)',(out/'runtime-controls.log').read_text());assert len(matches)==1
  costs=[int(x)for x in matches[0]]
  save('query-boundary-comparison.json',dict(actual=dict(work=costs[0],storageBytes=costs[1],storageCalls=costs[2]),old=read(previous/'prepared-query-cost.json'),unchanged=costs==[15457625,480861813,2647637]))
 finish('native-finding-only-groups-green',True)
finish('native-finding-only-complete-controls-resources-cancel-green',True)
