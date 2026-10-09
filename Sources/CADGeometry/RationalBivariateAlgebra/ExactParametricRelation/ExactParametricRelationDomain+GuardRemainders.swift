#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

extension ExactParametricRelationDomain {
    private func graphDegree<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, _ a: inout A) throws -> Int {
        var degree=0
        for term in law.terms {
            var total=0
            for power in term.powers {
                try a.consumeWork(1)
                let sum=total.addingReportingOverflow(power)
                guard !sum.overflow else { throw ExactParametricRelationFailure.countOverflow }
                total=sum.partialValue
            }
            degree=max(degree,total)
        }
        return degree
    }
    /// Only flat conjunctions entail their equalities; OR/NOT never admit this optimization.
    private func conjunctive<A: ExactScalarAdmission & ~Copyable>(_ predicate: ExactRealCellPredicate<Base>, _ a: inout A) throws -> Bool {
        for instruction in predicate.instructions {
            try a.consumeWork(1)
            switch instruction {
            case .not,.or: return false
            default: break
            }
        }
        return true
    }
    func graphRemainder<A: ExactScalarAdmission & ~Copyable>(_ original: Polynomial, equationIndex: Int,
        first: ExactParametricGraph<Base>, second: ExactParametricGraph<Base>,
        left: [Polynomial], right: [Polynomial], leftSlots: [Int], rightSlots: [Int],
        ring: ExactPolynomialDomain<Field>, proofs: inout [ExactParametricGuardRemainder<Base>], _ a: inout A) throws -> Polynomial {
        var equation=original
        var degree=try graphDegree(equation,&a)
        if degree <= 1 { return equation }
        for side in 0..<2 {
            let predicate=side == 0 ? first.predicate:second.predicate
            guard try conjunctive(predicate,&a) else { continue }
            for instruction in predicate.instructions {
                try a.consumeWork(1)
                guard case .sign(let index,.equal)=instruction else { continue }
                let guardLaw=side == 0 ? left[index]:right[index]
                let guardSlot=side == 0 ? leftSlots[index]:rightSlots[index]
                guard guardSlot >= 0 else { throw ExactParametricRelationFailure.invalidEvidence }
                if try ring.isZero(guardLaw,using:&a) { continue }
                for nonzero in 0..<2 {
                    try a.consumeWork(1)
                    if degree <= 1 { return equation }
                    let w=nonzero == 0 ? left[3]:right[3]
                    if try graphDegree(w,&a) == 0 { continue }
                    let dividend=try ring.multiplying(w,equation,using:&a)
                    let division=try ring.divided(dividend,by:guardLaw,using:&a)
                    let next=try graphDegree(division.remainder,&a)
                    if next < degree {
                        let count=proofs.count.addingReportingOverflow(1)
                        guard !count.overflow else { throw ExactParametricRelationFailure.countOverflow }
                        try storage(count.partialValue,ExactParametricGuardRemainder<Base>.self,&a)
                        proofs.append(.init(equationIndex:equationIndex,nonzeroGuardIndex:nonzero,
                            equalityGuardIndex:guardSlot,equation:equation,dividend:dividend,division:division))
                        equation=division.remainder; degree=next
                    }
                }
            }
        }
        return equation
    }
}
