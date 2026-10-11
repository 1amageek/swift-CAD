from pathlib import Path
import ast,hashlib,json,os,resource,signal,subprocess,time
root=Path.cwd();prior=root/'.build/s-ruled-closed-guide-seam-native-20261012-v2';out=root/'.build/s-ruled-closed-guide-seam-duplicates-native-20261012-v1';out.mkdir(exist_ok=False)
r=json.loads((prior/'failure-receipt.json').read_text());checks=r['checks'].copy();fresh=r['freshProduction'];runs=[]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,v):(out/n).write_text(json.dumps(v,indent=2)+'\n')
def admit(p,h=None):
 p=Path(p);h=h or sha(p);assert sha(p)==h,str(p);checks[str(p)]=h
def recheck():
 for n,h in checks.items():assert sha(n)==h,n
 for n,h in fresh.items():assert sha(n)==h,n
admit(__file__);admit(prior/'failure-receipt.json')
code=root/'Tests/OriginalPublicAcceptanceVerification/ClosedGuideSeamObservation.py';node=next(x for x in ast.parse(code.read_text()).body if isinstance(x,ast.FunctionDef) and x.name=='execute');exec(compile(ast.Module(body=[node],type_ignores=[]),str(code),'exec'))
s=(prior/'Proof.swift').read_text();start=s.index('        let raw:Raw =');end=s.index('    static func main()',start)
s=s[:start]+'''        var representatives:[Int] = [],classes:[Int] = []
        for i in family.graphs.indices {
            var canonical = i
            for j in representatives {
                if try identical(family.graphs[i].graph,family.graphs[j].graph,field:family.field,using:&a) { canonical=j;break }
            }
            if canonical == i { representatives.append(i) };classes.append(canonical)
        }
        print("EXACT_SOLVER_CLASSES",classes,"unique",representatives.count,"orderedClassPairs",representatives.count*representatives.count,"work",a.ledger.work,"storage",a.ledger.storageBytes)
    }
    static func identical(_ lhs:PublicLiftPlane.ExactParametricGraph<F>,_ rhs:PublicLiftPlane.ExactParametricGraph<F>,field:PublicLiftPlane.ExactAlgebraicScalarDomain<F>,using a:inout Admission) throws -> Bool {
        try a.checkpoint();try a.consumeWork(1)
        guard lhs.parameterCount == rhs.parameterCount,lhs.variableCount == rhs.variableCount else { return false }
        let x=lhs.predicate,y=rhs.predicate
        guard x.source.polynomials.count == y.source.polynomials.count,x.instructions.count == y.instructions.count,x.source.domains.count == y.source.domains.count else { return false }
        let ring=try ExactPolynomialDomain(field:field,variableCount:lhs.variableCount,using:&a)
        for i in x.source.polynomials.indices { if try !ring.equals(x.source.polynomials[i],y.source.polynomials[i],using:&a) { return false } }
        func sign(_ x:ExactRealCellSignRelation,_ y:ExactRealCellSignRelation)->Bool {
            switch (x,y) { case (.equal,.equal),(.notEqual,.notEqual),(.less,.less),(.lessOrEqual,.lessOrEqual),(.greater,.greater),(.greaterOrEqual,.greaterOrEqual):return true;default:return false }
        }
        for i in x.instructions.indices {
            try a.consumeWork(1)
            switch (x.instructions[i],y.instructions[i]) {
            case (.literal(let x),.literal(let y)):if x != y { return false }
            case (.sign(let x,let xr),.sign(let y,let yr)):if x != y || !sign(xr,yr) { return false }
            case (.not,.not),(.and,.and),(.or,.or):break
            default:return false
            }
        }
        func bound(_ x:PublicLiftPlane.ExactRealRootBound<PublicLiftPlane.ExactAlgebraicScalar<F>>,_ y:PublicLiftPlane.ExactRealRootBound<PublicLiftPlane.ExactAlgebraicScalar<F>>) throws -> Bool {
            try a.consumeWork(1)
            switch(x,y) { case (.negativeInfinity,.negativeInfinity),(.positiveInfinity,.positiveInfinity):return true
            case (.finite(let x),.finite(let y)):return try field.compare(x,y,using:&a) == .equal
            default:return false }
        }
        for i in x.source.domains.indices {
            try a.consumeWork(1);let l=x.source.domains[i],r=y.source.domains[i]
            guard l.includesLower == r.includesLower,l.includesUpper == r.includesUpper,l.isEmpty == r.isEmpty else { return false }
            if try !bound(l.lower,r.lower) || !bound(l.upper,r.upper) { return false }
        }
        return true
    }
'''+s[end:]
proof=out/'Proof.swift';proof.write_text(s);admit(proof)
cmd=json.loads((prior/'compile-proof.json').read_text());cmd=[str(proof) if x==str(prior/'Proof.swift') else x for x in cmd];cmd[cmd.index('-o')+1]=str(out/'DuplicateCount')
save('compile-proof.json',cmd);recheck()
try:
 execute('compile-proof',cmd);admit(out/'DuplicateCount');log=execute('run',[str(out/'DuplicateCount')]);recheck();save('receipt.json',dict(success=True,diagnosticOnly=True,cellComplete=False,checks=checks,freshProduction=fresh,runs=runs,postRunAdmission=True))
 print(log);print('RECEIPT',sha(out/'receipt.json'))
except BaseException:
 recheck();save('failure-receipt.json',dict(success=False,checks=checks,freshProduction=fresh,runs=runs,postRunAdmission=True));raise
