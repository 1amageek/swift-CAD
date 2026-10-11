#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Checked equality of all retained compiled predicate laws, programs and domains.
public struct OriginalIssuedGraphPredicateEquivalence: Sendable {
    public let original: ExactRealCellPredicate<OriginalExactScalarDomain>
    public let canonical: ExactRealCellPredicate<OriginalExactScalarDomain>
    public let depth: ExactScalarDepth
    private init(original:ExactRealCellPredicate<OriginalExactScalarDomain>,canonical:ExactRealCellPredicate<OriginalExactScalarDomain>,depth:ExactScalarDepth) {
        self.original=original;self.canonical=canonical;self.depth=depth
    }
    static func checked<A:ExactScalarAdmission & ~Copyable>(_ first:borrowing ExactRealCellPredicate<OriginalExactScalarDomain>,
        _ second:borrowing ExactRealCellPredicate<OriginalExactScalarDomain>,
        field:ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,using admission:inout A)
        throws(NativeExactRelationFailure) -> Self? {
        let first=copy first,second=copy second
        do {
            return try OriginalSourceProofAdmission.withBorrow(&admission) { a in
                try a.checkpoint();try a.consumeWork(1)
                guard first.source.variableCount == second.source.variableCount else { return nil }
                typealias Cells=ExactRealCellDomain<OriginalExactScalarDomain>
                let left=try Cells(retaining:first.source,using:&a),right=try Cells(retaining:second.source,using:&a)
                let lf=try left.coefficientField(of:first.source,using:&a),rf=try right.coefficientField(of:second.source,using:&a)
                _=try field.importing(lf.integer(0,using:&a),using:&a)
                _=try field.importing(rf.integer(0,using:&a),using:&a)
                let x=first,y=second
                try a.admitDepth(value:x.depth.value,coefficient:x.depth.coefficient)
                try a.admitDepth(value:y.depth.value,coefficient:y.depth.coefficient)
                guard x.source.polynomials.count == y.source.polynomials.count,
                    x.instructions.count == y.instructions.count,x.source.domains.count == y.source.domains.count else { return nil }
                for i in x.source.polynomials.indices {
                    try a.consumeWork(1)
                    let l=x.source.polynomials[i],r=y.source.polynomials[i]
                    try a.admitDepth(value:l.depth.value,coefficient:l.depth.coefficient)
                    try a.admitDepth(value:r.depth.value,coefficient:r.depth.coefficient)
                    guard l.terms.count == r.terms.count else { return nil }
                    for j in l.terms.indices {
                        let lt=l.terms[j],rt=r.terms[j]
                        guard lt.powers.count == rt.powers.count else { return nil }
                        for k in lt.powers.indices { try a.consumeWork(1);if lt.powers[k] != rt.powers[k] { return nil } }
                        if try field.compare(field.importing(lt.coefficient,using:&a),field.importing(rt.coefficient,using:&a),using:&a) != .equal { return nil }
                    }
                }
                for i in x.instructions.indices {
                    try a.consumeWork(1)
                    switch (x.instructions[i],y.instructions[i]) {
                    case (.literal(let l),.literal(let r)):if l != r { return nil }
                    case (.sign(let l,let lr),.sign(let r,let rr)):if l != r || !sameSign(lr,rr) { return nil }
                    case (.not,.not),(.and,.and),(.or,.or):break
                    default:return nil
                    }
                }
                for i in x.source.domains.indices {
                    try a.consumeWork(1)
                    let l=x.source.domains[i],r=y.source.domains[i]
                    try a.admitDepth(value:l.depth.value,coefficient:l.depth.coefficient)
                    try a.admitDepth(value:r.depth.value,coefficient:r.depth.coefficient)
                    guard l.includesLower == r.includesLower,l.includesUpper == r.includesUpper,l.isEmpty == r.isEmpty else { return nil }
                    if try !sameBound(l.lower,r.lower,field:field,using:&a)
                        || !sameBound(l.upper,r.upper,field:field,using:&a) { return nil }
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
                let result=Self(original:first,canonical:second,depth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .preserving(error) }
    }
    private static func sameSign(_ first: ExactRealCellSignRelation,_ second: ExactRealCellSignRelation) -> Bool {
        switch (first,second) {
        case (.equal,.equal),(.notEqual,.notEqual),(.less,.less),(.lessOrEqual,.lessOrEqual),(.greater,.greater),(.greaterOrEqual,.greaterOrEqual):return true
        default:return false
        }
    }
    private static func sameBound<A: ExactScalarAdmission & ~Copyable>(
        _ first: ExactRealRootBound<ExactAlgebraicScalar<OriginalExactScalarDomain>>,
        _ second: ExactRealRootBound<ExactAlgebraicScalar<OriginalExactScalarDomain>>,
        field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,using a: inout A) throws -> Bool {
        try a.consumeWork(1)
        switch (first,second) {
        case (.negativeInfinity,.negativeInfinity),(.positiveInfinity,.positiveInfinity):return true
        case (.finite(let l),.finite(let r)):
            return try field.compare(field.importing(l,using:&a),field.importing(r,using:&a),using:&a) == .equal
        default:return false
        }
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws(NativeExactRelationFailure) {
        do { try a.checkpoint();try a.admitDepth(value:depth.value,coefficient:depth.coefficient);try a.checkpoint() }
        catch { throw .preserving(error) }
    }
}
