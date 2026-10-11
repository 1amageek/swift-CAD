from pathlib import Path
import ast,hashlib,json,os,resource,signal,subprocess,time
root=Path('/private/tmp/cad-m4-m8-completion-20261010')
prior=root/'.build/s-ruled-closed-guide-seam-native-20261012-v2'
out=root/'.build/s-ruled-closed-guide-seam-native-20261012-v3';out.mkdir(exist_ok=False)
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
assert receipt['postRunAdmission'] and receipt['runs'][-1]['label']=='raw-observation' and receipt['runs'][-1]['exitCode']==1
log=(prior/'raw-observation.log').read_text();assert 'PASS complete fullUV issued cover and seven two-axis original graphs' in log and 'resourceLimit(CADGeometry.ExactResource.work)' in log
code=root/'Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamObservation.py'
node=next(x for x in ast.parse(code.read_text()).body if isinstance(x,ast.FunctionDef) and x.name=='execute')
exec(compile(ast.Module(body=[node],type_ignores=[]),str(code),'exec'))
command=json.loads((prior/'compile-proof.json').read_text());command=command[:command.index('-emit-executable')]+['-DGUIDE_SEAM_CHECKED_BOUNDARY_STOP','-typecheck',str(prior/'Proof.swift')]
save('admission.json',dict(checks=checks,freshProduction=fresh,historicalComparators=historical,rawObservation=str(prior/'failure-receipt.json'),rawObservationSHA256=sha(prior/'failure-receipt.json')))
save('compile-boundary-stop.json',command);recheck();diagnostic=execute('compile-boundary-stop',command,negative=True)
assert 'OriginalBSplineChartSelection' in diagnostic and 'OriginalRuledChartSelection' in diagnostic
recheck();save('receipt.json',dict(success=True,cellComplete=False,state='observed-original-source-and-raw-work-stop-plus-checked-boundary-type-stop',
 checks=checks,freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True,
 priorRawObservation=dict(path=str(prior/'failure-receipt.json'),sha256=sha(prior/'failure-receipt.json')),
 scope='Native observation only: actual constructor/same-parent/full cover/laws/layout succeeded; ordered raw product exhausted original work allowance before completion; separate checked boundary compile fails at Native selection type. No complete raw product or self residual claim.'))
print('FINAL_OBSERVATION_RECEIPT',sha(out/'receipt.json'))
