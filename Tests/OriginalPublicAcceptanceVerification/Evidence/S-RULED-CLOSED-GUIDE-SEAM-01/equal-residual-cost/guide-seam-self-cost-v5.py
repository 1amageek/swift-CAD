from pathlib import Path
import ast,difflib,hashlib,json,os,resource,signal,subprocess,time
root=Path.cwd();prior=root/'.build/s-ruled-closed-guide-seam-acceptance-native-20261012-v5';port=prior
out=root/'.build/s-ruled-closed-guide-seam-self-cost-native-20261012-v2';out.mkdir(exist_ok=False)
r=json.loads((prior/'failure-receipt.json').read_text());checks=r['checks'].copy();fresh=r['freshProduction'].copy();runs=[]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,v):(out/n).write_text(json.dumps(v,indent=2)+'\n')
def admit(p,h=None):
 p=Path(p);h=h or sha(p);assert sha(p)==h,str(p);checks[str(p)]=h
def recheck():
 for n,h in checks.items():assert sha(n)==h,n
 for n,h in fresh.items():assert sha(n)==h,n
admit(__file__);admit(prior/'failure-receipt.json');admit(port/'port-receipt.json')
query=root/'Sources/CADGeometry/OriginalSurfaceEmbedding/DefaultOriginalIssuedGraphSelfContactQuery.swift';refiner=root/'Sources/CADGeometry/NativeExactRelations/DefaultOriginalIssuedGraphParameterRefiner.swift'
for p in [query,refiner]:
 assert (port/p.name).read_text().endswith(p.read_text());admit(p)
qb=query.read_text();qb=qb[qb.index('        do {'):qb.rindex('\n    }')]
rb=refiner.read_text();rb=rb[rb.index('        do {'):rb.rindex('\n    }')]
q=qb.replace('<S,E,C,S,F,D>','<S,Law,Cover,S,Law,Cover>').replace('<S,E,C,F,D>','<S,Law,Cover,Law,Cover>')
q=q.replace('OriginalIssuedGraphParameterRefinement','GuideSeamPort.OriginalIssuedGraphParameterRefinement').replace('OriginalIssuedGraphSelfContacts','GuideSeamPort.OriginalIssuedGraphSelfContacts').replace('OriginalIssuedGraphSelfIdentityCompiler','GuideSeamPort.OriginalIssuedGraphSelfIdentityCompiler').replace('NativeExactRelationFailure','GuideSeamPort.NativeExactRelationFailure')
q=q.replace('            try a.checkpoint(); try raw.admitProof(limits: domainLimits, using: &a)','            a.stage="initial-raw-admission"; trace("query-entry",using:a)\n            try a.checkpoint(); try raw.admitProof(limits: domainLimits, using: &a)\n            trace("initial-raw-admit-done",using:a)')
q=q.replace('                let pair = raw.pairs[ordinal]','                let pair = raw.pairs[ordinal]\n                a.pair=ordinal;a.stage="diagonal"\n                print("SELF_PAIR",ordinal,"canonical",pair.canonicalFirstGraphIndex,pair.canonicalSecondGraphIndex,"rawSelected",pair.relation.projection.original.cells.count);trace("before-diagonal",using:a)')
q=q.replace('                var compiler =','                trace("after-diagonal",using:a);a.stage="identity-compile"\n                var compiler =',1)
q=q.replace('OriginalIssuedGraphPredicateEquivalence','GuideSeamPort.OriginalIssuedGraphPredicateEquivalence')
q=q.replace('                var reused:', '                trace("after-identity-compile-before-compare",using:a);a.stage="predicate-comparison"\n                var reused:',1)
q=q.replace('                    if let proof =', '                    a.candidates += 1\n                    print("SELF_CANDIDATE",ordinal,previous,"work",a.ledger.work);fflush(nil)\n                    if let proof =',1)
q=q.replace('                        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1,', '                        a.matches += 1\n                        print("SELF_MATCH",ordinal,previous,"work",a.ledger.work);fflush(nil)\n                        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1,',1)
q=q.replace('                if let reused { refined = reused }', '                if let reused { refined = reused;a.reuses += 1;trace("reuse-done",using:a) }',1)
q=q.replace('                    refined = try DefaultOriginalIssuedGraphParameterRefiner().refine', '                    a.unique += 1;a.stage="refine";a.refineStart=a.ledger.work;trace("before-unique-refine",using:a)\n                    refined = try costRefine',1)
q=q.replace('                predicates.append(predicate);', '                trace("after-refine",using:a)\n                predicates.append(predicate);',1)
b=rb.replace('<S,E,C,T,F,D>','<S,Law,Cover,S,Law,Cover>').replace('OriginalIssuedGraphParameterRefinement','GuideSeamPort.OriginalIssuedGraphParameterRefinement').replace('NativeExactRelationFailure','GuideSeamPort.NativeExactRelationFailure')
b=b.replace('            try raw.admitProof(limits: limits, using: &admission)','            trace("refiner-before-raw-admit",using:admission);admission.stage="refiner-raw-admission"\n            try raw.admitProof(limits: limits, using: &admission)\n            trace("refiner-after-raw-admit",using:admission);admission.stage="refine-pullback"',1)
methods='''    static func trace(_ stage:String,using a:borrowing Admission) {
        print("SELF_COST pair=",a.pair,"stage=",stage,"work=",a.ledger.work,"storage=",a.ledger.storageBytes,"candidates=",a.candidates,"matches=",a.matches,"reuses=",a.reuses,"unique=",a.unique,"refineStart=",a.refineStart);fflush(nil)
    }
    // Diagnostic transcription; every actual operation and admission stays ordered.
    static func costQuery(in raw:Raw,excluding identities:[OriginalParameterIdentity<S,F>],domainLimits:OriginalDomainIdentityLimits,
        cellLimits:ExactRealCellLimits,topologyLimits:ExactRealTopologyLimits,using a:inout Admission)
        throws(GuideSeamPort.NativeExactRelationFailure) -> GuideSeamPort.OriginalIssuedGraphSelfContacts<S,Law,Cover,Law,Cover> {
'''+q+'''
    }
    static func costRefine(in raw:borrowing Raw,pairOrdinal:Int,matching predicate:borrowing ExactRealCellPredicate<F>,
        limits:OriginalDomainIdentityLimits,cellLimits:ExactRealCellLimits,topologyLimits:ExactRealTopologyLimits,using admission:inout Admission)
        throws(GuideSeamPort.NativeExactRelationFailure) -> GuideSeamPort.OriginalIssuedGraphParameterRefinement<S,Law,Cover,S,Law,Cover> {
'''+b+'''
    }
'''
s=(prior/'Proof.swift').read_text().replace('ClosedGuideSeamAcceptance','ClosedGuideSeamSelfCostObservation')
s=s.replace('        var ledger: ExactScalarLedger','        var candidates=0,matches=0,reuses=0,unique=0,refineStart=0\n        var pair = -1\n        var stage = "preparation"\n        var ledger: ExactScalarLedger',1)
s=s.replace('mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }','''mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) {
            do { try ledger.consumeWork(n) }
            catch { print("SELF_EXHAUSTED pair=",pair,"stage=",stage,"work=",ledger.work,"requested=",n,"storage=",ledger.storageBytes,"candidates=",candidates,"matches=",matches,"reuses=",reuses,"unique=",unique,"refineStart=",refineStart);fflush(nil);throw error }
        }''',1)
s=s.replace('    static func observe() throws {',methods+'    static func observe() throws {',1)
s=s.replace('GuideSeamPort.DefaultOriginalIssuedGraphSelfContactQuery().contacts(in:raw','costQuery(in:raw',1)
proof=out/'Proof.swift';proof.write_text(s);admit(proof)
for name,original,changed in [('Query',qb,q),('Refiner',rb,b)]:
 (out/(name+'OriginalBody.txt')).write_text(original);(out/(name+'Instrumentation.diff')).write_text(''.join(difflib.unified_diff(original.splitlines(True),changed.splitlines(True),fromfile='admitted-'+name,tofile='diagnostic-'+name)))
for p in out.iterdir():
 if p.is_file():admit(p)
code=root/'Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamObservation.py';node=next(x for x in ast.parse(code.read_text()).body if isinstance(x,ast.FunctionDef) and x.name=='execute');exec(compile(ast.Module(body=[node],type_ignores=[]),str(code),'exec'))
command=json.loads((prior/'compile-proof.json').read_text());command=[str(proof) if x==str(prior/'Proof.swift') else x for x in command];command[command.index('-o')+1]=str(out/'SelfCost')
save('admission.json',dict(checks=checks,freshProduction=fresh,scope='Diagnostic-only exact self/refiner transcription, same independent query ledger and all49pairs; no algorithm or cap change'))
save('compile-proof.json',command)
try:
 recheck();execute('compile-proof',command);admit(out/'SelfCost');save('proof-receipt.json',dict(checks=checks,freshProduction=fresh,runs=runs))
 log=execute('runtime',[str(out/'SelfCost')],negative=True)
 assert 'SELF_EXHAUSTED' in log and 'resourceLimit(CADGeometry.ExactResource.work)' in log
 recheck();save('receipt.json',dict(success=True,diagnosticOnly=True,cellComplete=False,checks=checks,freshProduction=fresh,runs=runs,postRunAdmission=True,exhaustion=[x for x in log.splitlines() if x.startswith('SELF_EXHAUSTED')],lastMarkers=[x for x in log.splitlines() if x.startswith('SELF_')][-12:]))
 print('RECEIPT',sha(out/'receipt.json'))
except BaseException:
 recheck();save('failure-receipt.json',dict(success=False,diagnosticOnly=True,cellComplete=False,checks=checks,freshProduction=fresh,runs=runs,postRunAdmission=True));raise
