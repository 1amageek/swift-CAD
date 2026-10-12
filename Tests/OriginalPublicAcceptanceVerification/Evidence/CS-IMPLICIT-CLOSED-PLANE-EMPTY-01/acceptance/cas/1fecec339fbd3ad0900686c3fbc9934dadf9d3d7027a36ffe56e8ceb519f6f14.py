#!/usr/bin/env python3
"""Correct one Clang-forwarded argument; preserve the failed v1 transaction."""
import hashlib,json
from pathlib import Path
R=Path('/private/tmp/cad-m4-m8-completion-20261010');V=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v1';O=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v2'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def save(n,v):(O/n).write_text(json.dumps(v,indent=2)+'\n')
def bind(p):return dict(path=str(p),sha256=sha(p),bytes=Path(p).stat().st_size)
assert sha(V/'profile.json')=='4eddf899eb75558a761a891459619b8e842a783f4d3e3a817de5b3251187bead'
assert sha(V/'receipt.json')=='7bdd3f33ed8fac5feb1e779c95a60777ea5968a544ba395cacd456d80951bb47'
for n in ['geometry','source','upper','fixture']:(O/n).mkdir(exist_ok=True)
p=read(V/'profile.json');diffs=[]
for name in p['commands']:
 old=read(V/(name+'-command.json'));new=[]
 for token in old:
  if token.startswith(str(V)) and not (token.endswith('.swift') and Path(token).exists()):token=token.replace(str(V),str(O),1)
  new.append(token)
 if name in ['geometry-object','geometry-module']:
  i=new.index('-package-name');assert new[i-1]=='-Xcc';new.insert(i,'-g')
  diffs.append(dict(command=name,semanticDiff=['insert -g between -Xcc and -package-name'],priorCommand=bind(V/(name+'-command.json'))))
 save(name+'-command.json',new);p['commands'][name]=bind(O/(name+'-command.json'))
probe=read(O/'geometry-object-command.json')+['-driver-print-jobs'];save('driver-jobs-command.json',probe)
p.update(state='OUTPUT-ARGUMENT-CORRECTION-PREPARED-NO-CODEGEN',priorApprovedProfile=bind(V/'profile.json'),priorFailure=bind(V/'receipt.json'),outputPathChanges='Only fresh outputs, private caches, and fresh import directories move to v2; all existing .swift input paths and response file bytes are retained.',causalCorrection=diffs,
 priorSpentGeometry=dict(wallSeconds=read(V/'receipt.json')['runs'][0]['elapsedSeconds'],ownedCPUSeconds=read(V/'receipt.json')['runs'][0]['sampledOwnedCPUSeconds']),remainingBudgetRule='Debit the prior driver stage and this bounded diagnostic from the same original 1200-second Geometry wall/owned-CPU allowance. No increased ceiling.',driverOnlyCommand=bind(O/'driver-jobs-command.json'),actualCodegenExecutions=0)
save('profile-pre-probe.json',p);save('preparation.json',dict(prepareScript=bind(Path(__file__).resolve()),priorApprovedProfile=bind(V/'profile.json'),priorFailure=bind(V/'receipt.json'),probeCommand=bind(O/'driver-jobs-command.json')))
print(json.dumps(dict(state='PREPARED-DRIVER-ONLY',profileSHA256=sha(O/'profile-pre-probe.json'),commandSHA256=sha(O/'driver-jobs-command.json'))))
