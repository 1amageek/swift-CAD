#!/usr/bin/env python3
"""Freeze the observed driver layout without executing any printed frontend job."""
from pathlib import Path
import json,hashlib
R=Path('/private/tmp/cad-m4-m8-completion-20261010');V=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v1';O=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v2'
def read(p):return json.loads(Path(p).read_text())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bind(p):return dict(path=str(p),sha256=sha(p),bytes=Path(p).stat().st_size)
def save(n,v):(O/n).write_text(json.dumps(v,indent=2)+'\n')
p=read(O/'profile-pre-probe.json');driver=read(O/'driver-final-jobs-receipt.json');assert driver['exitCode']==0 and driver['actualCodegenExecutions']==0 and driver['preAndPostHashesMatch']
jobs=read(O/'printed-final-jobs.json');assert len(jobs)==1;job=jobs[0];assert job[:3][1:]==['-frontend','-c'];assert '-primary-file'not in job;assert job[job.index('-num-threads')+1]=='14';assert job[job.index('-package-name')+1]=='nativeexactrelationverification'
retained=[];lists={}
for flag in ['-filelist','-supplementary-output-file-map','-output-filelist']:
 original=Path(job[job.index(flag)+1]);target=O/('final-'+original.name+'.txt');target.write_bytes(original.read_bytes());retained.append(dict(flag=flag,driverTemporaryPath=str(original),retained=bind(target)));lists[flag]=target
inputs=lists['-filelist'].read_text().splitlines();outputs=lists['-output-filelist'].read_text().splitlines();expected=read(V/'geometry-inputs.json');assert inputs==[b['compiledInput']for b in expected];assert len(inputs)==len(outputs)==1651
outmap=read(O/'geometry/output-file-map.json');assert outputs==[outmap[v]['object']for v in inputs]
assert not list((O/'geometry').glob('**/*.o'))
command=read(O/'driver-final-jobs-command.json');assert command[-1]=='-driver-print-jobs';save('geometry-object-command.json',command[:-1])
module=read(O/'geometry-module-command.json');module[module.index('-num-threads')+1]='14';save('geometry-module-command.json',module)
llvm_ar=Path(p['toolchain']['executable']).with_name('llvm-ar');assert llvm_ar.exists()
archive_inputs=O/'geometry/archive-inputs.txt';archive_inputs.write_text(''.join(v+'\n'for v in outputs)+str(O/'geometry/CADGeometry.swiftmodule.o')+'\n')
save('geometry-archive-command.json',[str(llvm_ar),'-rcs',str(O/'geometry/libCADGeometryClosedWMO.a'),'@'+str(archive_inputs)])
for name in p['commands']:p['commands'][name]=bind(O/(name+'-command.json'))
usage=[dict(stage='v1-driver-object',receipt=bind(V/'receipt.json'),wallSeconds=read(V/'receipt.json')['runs'][0]['elapsedSeconds'],ownedCPUSeconds=read(V/'receipt.json')['runs'][0]['sampledOwnedCPUSeconds'])]
for n in ['driver-jobs-receipt.json','driver-partition-jobs-receipt.json','driver-final-jobs-receipt.json']:
 v=read(O/n);usage.append(dict(stage=n,receipt=bind(O/n),wallSeconds=v['elapsedSeconds'],ownedCPUSeconds=v['sampledOwnedCPUSeconds']))
wall=sum(v['wallSeconds']for v in usage);cpu=sum(v['ownedCPUSeconds']for v in usage)
save('driver-layout.json',dict(driverReceipt=bind(O/'driver-final-jobs-receipt.json'),printedJob=bind(O/'printed-final-jobs.json'),retainedTemporaryLists=retained,inputCount=len(inputs),outputCount=len(outputs),jobs=1,primaryFiles=0,threads=14,module='CADGeometry',package='nativeexactrelationverification',driverWMOFlag=True,frontendExplicitWMOFlag=False,frontendModeInterpretation='Driver-selected full-module compilation: one frontend receives all1651 sources and no-primary-file. Printed jobs were not executed.',inputsExactlyEqualFrozen1651=True,outputsExactlyEqualPrivateM6Map=True,codegen=0,actualObjects=0))
p.update(state='FROZEN-OUTPUT-ARGUMENT-CORRECTION-PENDING-ROOT-GO',actualCodegenExecutions=0,driverObservation=bind(O/'driver-layout.json'),diagnostics=[dict(finding='Preparation filter removed -g from the forwarded pair -Xcc -g, causing -package-name to be forwarded to Clang. It was a distinct preparation defect; restoring -g did not resolve the single-output driver refusal.',fixedCommands=['geometry-object','geometry-module']),dict(finding='Single -o was rejected after the forwarded argument was fixed. Existing M6 output map with private paths is accepted by the driver. Actual final job has all1651 inputs and1651 outputs with original threads14.',fixedCommands=['geometry-object','geometry-archive']),dict(finding='Darwin ar does not provide the required Wasm archive index in the independently observed normal-WASM path; fixed Swift6.4 llvm-ar is selected without executing it here.',fixedCommands=['geometry-archive'])],
 geometryBudgetCarry=dict(originalWallSeconds=1200,originalOwnedCPUSeconds=1200,originalResidentSumBytes=8589934592,priorStages=usage,alreadyUsedWallSeconds=wall,alreadyUsedOwnedCPUSeconds=cpu,remainingWallSeconds=1200-wall,remainingOwnedCPUSeconds=1200-cpu,rule='Seed the next shared Geometry sequence clock/CPU with these debits; do not reset or increase the original allowance.'),
 actualSelectedInputs=dict(geometryInputCount=1651,changed3Count=3,unchangedHistoricalSourceCount=1648,sourceAuthority='Unchanged M6 Embedded hashes plus the same three selected current body hashes',responseFile=str(V/'geometry/inputs.txt')))
p['toolchain']['geometryCodegenThreads']=14;p['toolchain']['archiver']=bind(llvm_ar)
p['counts']['plannedFreshGeometryCodegenObjects']=1651;p['counts']['plannedFreshGeometryArchiveMembers']=1652;p['counts']['plannedFreshGeometryModuleWrapObjects']=1;p['counts']['geometrySourceCompilationJobs']=1
p['uncertainty'].update(objectCount='Actual driver output-filelist has1651 paths. No object has been generated; the archive will also retain one fresh modulewrap.',commandValidity='Geometry object driver planning passed. Frontend, module emission, modulewrap, llvm-ar, imports, link, and runtime remain unobserved.')
p['geometryCommandConstruction']='Exact fixed source set; original M6 output-file-map roles rewritten only to private paths, original threads14, restored Clang -g pair, Swift6.4 llvm-ar response file. No primary-only compilation or historical object mixing.'
p['artifacts'].update(correctedPreparation=bind(O/'PrepareV2.py'),layoutFreezeScript=bind(Path(__file__).resolve()),outputFileMap=bind(O/'geometry/output-file-map.json'),archiveResponseFile=bind(archive_inputs),driverLayout=bind(O/'driver-layout.json'))
save('profile.json',p)
print(json.dumps(dict(profileSHA256=sha(O/'profile.json'),driverLayoutSHA256=sha(O/'driver-layout.json'),commands={k:v['sha256']for k,v in p['commands'].items()},alreadyUsedWallSeconds=wall,alreadyUsedCPUSeconds=cpu,remainingWallSeconds=1200-wall,remainingCPUSeconds=1200-cpu,codegen=0)))
