#!/usr/bin/env python3
"""Observe cumulative pair/stage work under the unchanged original ledger."""
from pathlib import Path
import ast,hashlib,json,os,resource,signal,subprocess,time
root=Path(__file__).resolve().parents[2]
prior=root/'.build/s-ruled-closed-guide-seam-native-20261012-v2'
out=root/'.build/s-ruled-closed-guide-seam-cost-native-20261012-v1'
assert out.is_dir() and not (out/'runs.json').exists()
receipt=json.loads((prior/'failure-receipt.json').read_text())
checks,fresh,runs,historical=receipt['checks'].copy(),receipt['freshProduction'].copy(),[],receipt['historicalComparators']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,v):(out/n).write_text(json.dumps(v,indent=2)+'\n')
def admit(p,h=None):
 p=Path(p);h=h or sha(p);assert sha(p)==h,str(p);checks[str(p)]=h
def recheck():
 for n,h in checks.items():assert sha(n)==h,n
 for n,h in fresh.items():assert sha(n)==h,n
admit(prior/'failure-receipt.json');admit(__file__)
fixture=Path(__file__).with_suffix('.swift');admit(fixture)
original=root/'Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamObservation.swift'
admit(original,'434322d00746b6d0178dbc360f396d441a8392006ac37ddf3bf1ff9c7cb10b76')
resolver=root/'Sources/CADGeometry/NativeExactRelations/DefaultOriginalIssuedGraphRelationResolver.swift'
cachedResolver=root/'.build/cs-draft-zero-ruled-native-20261011-v2/generated/DefaultOriginalIssuedGraphRelationResolver.swift'
assert cachedResolver.read_text().endswith(resolver.read_text())
l5=root/'Sources/CADGeometry/RationalBivariateAlgebra/ExactParametricRelation/ExactParametricRelationDomain+Graphs.swift'
cachedL5=next((root/'.build/cs-poly-01-ordinary-accepted-20261011/native/compiler-source-snapshot').glob('*-ExactParametricRelationDomain+Graphs.swift'))
start='extension ExactParametricRelationDomain: ExactParametricGraphResolving'
assert l5.read_text().split(start)[1]==cachedL5.read_text().split(start)[1]
for p in [resolver,cachedResolver,l5,cachedL5,root/'.build/create-guide-cost-observation.py']:
 admit(p)
for p in out.iterdir():
 if p.is_file():admit(p)
code=root/'Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamObservation.py'
node=next(x for x in ast.parse(code.read_text()).body if isinstance(x,ast.FunctionDef) and x.name=='execute')
exec(compile(ast.Module(body=[node],type_ignores=[]),str(code),'exec'))
prefix=(prior/'Proof.swift').read_text().split(original.read_text())[0]
proof=out/'Proof.swift';proof.write_text(prefix+fixture.read_text());admit(proof)
command=json.loads((prior/'compile-proof.json').read_text())
command=[str(proof) if x==str(prior/'Proof.swift') else str(out/'CostObservation') if x==str(prior/'Observation') else x for x in command]
command[command.index('-o')+1]=str(out/'CostObservation')
save('compile-proof.json',command)
save('admission.json',dict(checks=checks,freshProduction=fresh,historicalComparators=historical,
 scope='Diagnostic transcription with read-only pair/stage markers; same original single ledger, accounting, preparation and full49 request. No production acceptance.',
 wallLimitSeconds=120,cpuLimitSecondsPerProcess=120))
try:
 recheck();execute('compile-proof',command);admit(out/'CostObservation')
 save('proof-receipt.json',dict(state='successful-diagnostic-compile',checks=checks,runs=runs))
 log=execute('cost-observation',[str(out/'CostObservation')],negative=True)
 assert 'COST_EXHAUSTED' in log and 'resourceLimit(CADGeometry.ExactResource.work)' in log
 recheck();save('receipt.json',dict(success=True,cellComplete=False,diagnosticOnly=True,checks=checks,
  freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True,
  exhaustion=[x for x in log.splitlines() if 'COST_EXHAUSTED' in x],lastMarkers=[x for x in log.splitlines() if x.startswith('COST ')][-8:]))
 print('COST_RECEIPT',sha(out/'receipt.json'))
except BaseException:
 recheck();save('failure-receipt.json',dict(success=False,cellComplete=False,diagnosticOnly=True,checks=checks,
  freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True))
 raise
