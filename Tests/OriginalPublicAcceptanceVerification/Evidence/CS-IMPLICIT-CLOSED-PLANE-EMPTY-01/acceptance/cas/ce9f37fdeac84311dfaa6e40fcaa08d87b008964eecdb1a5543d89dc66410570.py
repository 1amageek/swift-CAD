#!/usr/bin/env python3
"""Prepare and run generation-bound Native closed-host empty acceptance stages."""
import argparse, hashlib, importlib.util, json, os, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT/'Tests/OriginalPublicAcceptanceVerification'
CELL = 'CS-IMPLICIT-CLOSED-PLANE-EMPTY-01'
PRIOR = ROOT/'.build/cs-implicit-closed-value-native-20261013-v2'
OUT = ROOT/'.build/cs-implicit-closed-acceptance-native-20261013-v1'
FIXTURE = TESTS/'ImplicitClosedPlaneEmptyAcceptance.swift'
BOUNDING_DRIVER = TESTS/'ImplicitReverseDyadicParabolaAcceptance.py'
GROUPS = ['complete','dispatch','source','requests','resources','readmission','cancel-entry','cancel-final','cancel-reader','lifetime','changed-controls']
SOURCE_HASHES = {
 'OriginalImplicitHostExclusionSnapshotProvider.swift':'18acd55c3889cce12b8fc7eff6b025af69a96fdcea5ff15b34b0031fb057bb71',
 'OriginalImplicitHostPlaneSeparationIssuing.swift':'bc7766b5c15c4a8de47c7dcb64f2d78aab4c60a26accc1de759441de8fc26f81',
 'OriginalImplicitHostPlaneSeparationReceipt.swift':'337ecb4214f6faa2f64f0621dfb885ee08f4445f47d52088bd8d201520c76041',
 'DefaultOriginalImplicitHostPlaneSeparationIssuer.swift':'50556c40d00a1ba64f92b46cf8501fca1b4dff5ae293c4b7eee3f4ea63a051de'}
UPPER_HASHES = {
 'OriginalImplicitHostPlaneExclusion.swift':'275c42a7dd5ed29b442804300feff37bf246de9616e0c35c511f0c937ade177c',
 'OriginalImplicitHostPlaneExclusionReading.swift':'b6fbcdd6ea7dd488d36784241a7e56acff08f0f2cabb319c2b15451f1fb7ca6f',
 'OriginalImplicitHostPlanePublicProducer.swift':'8c7d9a9ee51f4b1ef8fae5b7261eeafdcd0857e9ece3ffd634ab83d932cb0bfe',
 'CurveSurfaceIntersectionResult.swift':'ecd73512f8b188457d7c854aac1e3f93980457f8845de0046fd808c44550f28f',
 'OriginalImplicitCurvePublicProducer.swift':'e54826ec13073bfa4c61ad99263562bf8bba78b34f6bf65c5aba2d876c64555a'}
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def save(path,value): Path(path).write_text(json.dumps(value,indent=2)+'\n')
def admit(checks,path,expected=None):
 actual=sha(path); assert expected is None or actual==expected, 'Changed input: '+str(path)
 checks[str(path)]=actual

def prepare():
 assert not (OUT/'source-compile-started.json').exists(), 'No rewriting started profile'
 OUT.mkdir(parents=True,exist_ok=True)
 value=TESTS/'Evidence'/CELL/'value'
 raw=read(PRIOR/'receipt.json');base=read(value/'bindings.json');manifest=read(value/'manifest.json')
 assert raw['postHashesMatch'] and raw['ordinaryPublicCalls']==1
 archived={(v.get('originalPath',k),v['sha256']):ROOT/v['path']for k,v in manifest['files'].items()}
 historical=[]; checks={}
 for path,digest in raw['checks'].items():
  retained=archived.get((path,digest))
  if retained is not None and Path(path).suffix in {'.swift','.py','.json','.log','.txt','.md','.mjs'}:
   admit(checks,retained,digest);historical.append(dict(originalPath=path,sha256=digest,retainedPath=str(retained)))
  else: checks[path]=digest
 for path in [value/'summary.json',value/'manifest.json',value/'bindings.json',PRIOR/'receipt.json',BOUNDING_DRIVER,FIXTURE,Path(__file__).resolve()]:admit(checks,path)
 for path,digest in raw['products'].items():checks[path]=digest
 oldcommand=read(PRIOR/'compile-link-command.json')
 flags=oldcommand[:oldcommand.index('-emit-executable')]
 sourceowner=ROOT/'.build/cs-implicit-reverse-acceptance-native-20261013-v1/source'
 assert str(sourceowner) in flags
 originals={Path(b['originalPath']).name:b for b in base['unchangedUpperAndSource6CompiledBindings']}
 snapshot=originals['OriginalImplicitCurveSnapshot.swift']
 sourcebytes=(ROOT/snapshot['compiledInput']['path']).read_bytes();originalbytes=(ROOT/snapshot['original']['path']).read_bytes()
 assert sourcebytes.endswith(originalbytes)
 sourceprefix=sourcebytes[:-len(originalbytes)]+b'\n@testable import ImplicitSourcePhase\n'
 sourcebindings=[];(OUT/'source').mkdir(exist_ok=True)
 for name,expected in SOURCE_HASHES.items():
  original=ROOT/'Sources/CADGeometry/OriginalSourceIssuance'/name;admit(checks,original,expected)
  generated=OUT/'source'/name;generated.write_bytes(sourceprefix+original.read_bytes());admit(checks,generated)
  sourcebindings.append(dict(original=str(original),originalSHA256=expected,generated=str(generated),generatedSHA256=sha(generated),prefixSHA256=hashlib.sha256(sourceprefix).hexdigest()))
 sourceflags=flags.copy();sourceflags[sourceflags.index('-module-cache-path')+1]=str(OUT/'source-module-cache')
 sourcecommand=sourceflags+['-emit-module','-emit-library','-static','-module-name','ImplicitHostPlaneSourcePhase']+[v['generated']for v in sourcebindings]+['-emit-module-path',str(OUT/'source/ImplicitHostPlaneSourcePhase.swiftmodule'),'-o',str(OUT/'source/libImplicitHostPlaneSourcePhase.a')]
 save(OUT/'source-command.json',sourcecommand);admit(checks,OUT/'source-command.json')
 sourcechecks=dict(checks)
 sourcepremise=dict(checks=sourcechecks,bindings=sourcebindings,actualSourceBodyCount=4,reusedSource6=base['unchangedUpperAndSource6CompiledBindings'][:6],source6Recompile=0,lowerCodegen=0,currentSnapshotOwner='ImplicitSourcePhase',sameSealedSourceOwner='RetainedHostAdapters',proofAdmissionOwner='AngularSourcePhase',historicalBindings=historical)
 save(OUT/'source-premises.json',sourcepremise)
 # Keep actual selected-body generated prefixes, replace only their original current suffixes.
 upperbindings=[];generated=[];commonprefix=None
 for path in [v for v in oldcommand if v.endswith('.swift')][:-2]:
  prior=Path(path);binding=originals[prior.name]
  original=Path(binding['originalPath']);old=(ROOT/binding['original']['path']).read_bytes()
  data=prior.read_bytes();assert data.endswith(old)
  prefix=data[:-len(old)]+b'\n@testable import ImplicitHostPlaneSourcePhase\n'
  if commonprefix is None:commonprefix=prefix
  if prior.name in UPPER_HASHES:admit(checks,original,UPPER_HASHES[prior.name])
  else:admit(checks,original,binding['original']['sha256'])
  target=OUT/prior.name;target.write_bytes(prefix+original.read_bytes());admit(checks,target)
  generated.append(str(target));upperbindings.append(dict(original=str(original),originalSHA256=sha(original),generated=str(target),generatedSHA256=sha(target),prefixSHA256=hashlib.sha256(prefix).hexdigest()))
 assert len(upperbindings)==56
 for relative in ['NativeExactRelations/OriginalImplicitHostPlaneExclusion.swift','NativeExactGeometricRelations/OriginalImplicitHostPlaneExclusionReading.swift','NativeExactGeometricRelations/OriginalImplicitHostPlanePublicProducer.swift']:
  original=ROOT/'Sources/CADGeometry'/relative;admit(checks,original,UPPER_HASHES[original.name])
  target=OUT/original.name;target.write_bytes(commonprefix+original.read_bytes());admit(checks,target)
  generated.append(str(target));upperbindings.append(dict(original=str(original),originalSHA256=sha(original),generated=str(target),generatedSHA256=sha(target),prefixSHA256=hashlib.sha256(commonprefix).hexdigest()))
 oldproof=Path(oldcommand[-2]) if oldcommand[-2].endswith('.swift') else Path(next(v for v in oldcommand if Path(v).name=='Proof.swift'))
 oldfixture=TESTS/'ImplicitClosedPlaneEmptyValueObservation.swift';proofbytes=oldproof.read_bytes();assert proofbytes.endswith(oldfixture.read_bytes())
 proof=OUT/'Proof.swift';proof.write_bytes(proofbytes[:-len(oldfixture.read_bytes())]+b'\n@testable import ImplicitHostPlaneSourcePhase\n'+FIXTURE.read_bytes());admit(checks,proof)
 selector=Path(next(v for v in oldcommand if Path(v).name=='ActualSelectorDeclineAdapters.swift'));admit(checks,selector)
 upperflags=flags.copy();upperflags[upperflags.index('-module-cache-path')+1]=str(OUT/'upper-module-cache')
 archives=[v for v in oldcommand if v.endswith('.a')]
 assert len(archives)==14 and str(PRIOR/'libCachedCADGeometryValue.a') in archives
 command=upperflags+['-I',str(OUT/'source'),'-emit-executable','-module-name','ImplicitClosedPlaneEmptyAcceptance']+generated+[str(selector),str(proof)]+archives+[str(OUT/'source/libImplicitHostPlaneSourcePhase.a'),'-o',str(OUT/'Acceptance')]
 assert len(upperbindings)==59 and sum(v.endswith('.swift')for v in command)==61
 save(OUT/'upper-command.json',command);admit(checks,OUT/'upper-command.json')
 save(OUT/'upper-premises.json',dict(checks=checks,bindings=upperbindings,upperBodies=59,swiftInputs=61,sourceModuleReceipt=str(OUT/'source-compile-receipt.json'),reusedSource6Module=str(sourceowner/'ImplicitSourcePhase.swiftmodule'),source6Recompile=0,lowerCodegen=0,reusedSelected3Products=raw['products'],originalObservation=str(TESTS/'Evidence'/CELL/'observation/summary.json'),connectionObservation=str(TESTS/'Evidence'/CELL/'connection/summary.json'),valueObservation=str(value/'summary.json'),groups=GROUPS,historicalBindings=historical))
 (OUT/'driver-at-prepare.py').write_bytes(Path(__file__).read_bytes());(OUT/'fixture-at-prepare.swift').write_bytes(FIXTURE.read_bytes())
 save(OUT/'freeze.json',dict(state='prepared-pending-root-GO',sourceBodies={v['original']:v['originalSHA256']for v in sourcebindings},upperBodies={v['original']:v['originalSHA256']for v in upperbindings},fixtureSHA256=sha(FIXTURE),runnerSHA256=sha(__file__),source6Recompile=0,lowerCodegen=0))
 print(json.dumps(dict(state='PREPARED-NO-EXECUTION',sourceBodies=4,upperBodies=59,swiftUpperInputs=61,archives=15,fixtureSHA256=sha(FIXTURE),runnerSHA256=sha(__file__),sourceCommandSHA256=sha(OUT/'source-command.json'),upperCommandSHA256=sha(OUT/'upper-command.json'))))

def execute(stage,groups):
 freeze=read(OUT/'freeze.json');assert freeze['state']=='frozen-root-GO'
 assert sha(FIXTURE)==freeze['fixtureSHA256']and sha(__file__)==freeze['runnerSHA256']
 spec=importlib.util.spec_from_file_location('closed_bounded_stages',BOUNDING_DRIVER);helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper);helper.OUT=OUT
 meta=read(OUT/('source-premises.json'if stage=='source'else'upper-premises.json'));checks=dict(meta['checks']);admit(checks,OUT/('source-premises.json'if stage=='source'else'upper-premises.json'));admit(checks,OUT/'freeze.json')
 snapshot=OUT/('driver-at-'+stage+'.py');snapshot.write_bytes(Path(__file__).read_bytes());admit(checks,snapshot)
 if stage=='source':
  result=helper.bounded('source-compile',read(OUT/'source-command.json'),checks)
  assert result['exitCode']==0
 elif stage=='upper':
  source=read(OUT/'source-compile-receipt.json');assert source['exitCode']==0
  checks.update(source['products']);admit(checks,OUT/'source-compile-receipt.json')
  result=helper.bounded('upper-compile',read(OUT/'upper-command.json'),checks)
  if result['exitCode']==0:result['products']={str(OUT/'Acceptance'):sha(OUT/'Acceptance')};save(OUT/'upper-compile-receipt.json',result)
  assert result['exitCode']==0
 else:
  source=read(OUT/'source-compile-receipt.json');upper=read(OUT/'upper-compile-receipt.json');assert upper['exitCode']==0
  checks.update(source['products']);admit(checks,OUT/'source-compile-receipt.json');admit(checks,OUT/'upper-compile-receipt.json')
  os.environ['CAD_PROOF_REUSE_NATIVE_CONTROLS']='1'
  for group in groups:
   assert group in GROUPS
   result=helper.bounded('runtime-'+group,[str(OUT/'Acceptance'),group],checks,upper['products'])
   assert result['exitCode']==0, 'Actual group stop: '+group
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--stage',choices=['prepare','source','upper','runtime'],default='prepare');parser.add_argument('--groups',default=','.join(GROUPS));args=parser.parse_args()
 if args.stage=='prepare':prepare()
 else:execute(args.stage,args.groups.split(','))
