#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension OriginalPiScalarDomain {
    public func sign<A: ExactScalarAdmission & ~Copyable>(of input: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactSign {
        let x = copy input
        return try Self.query(&admission) { a in
            try require(x,&a)
            if try owner.ring.isZero(x.numerator,using:&a) { return .zero }
            if x.numerator.termCount == 1,x.denominator.termCount == 1,
                x.numerator.terms[0].powers[0] == 0,x.denominator.terms[0].powers[0] == 0 {
                let n = try owner.rationals.sign(of:x.numerator.terms[0].coefficient,using:&a)
                let d = try owner.rationals.sign(of:x.denominator.terms[0].coefficient,using:&a)
                return n == d ? .positive : .negative
            }
            var refinement = try OriginalPiRefinement(&a)
            while true {
                try a.checkpoint()
                let interval = try refinement.next(&a)
                if let n = try enclosed(x.numerator,at:interval,&a).sign(owner.rationals,&a),
                    let d = try enclosed(x.denominator,at:interval,&a).sign(owner.rationals,&a) {
                    return n == d ? .positive : .negative
                }
            }
        }
    }
    func enclosed<A: ExactScalarAdmission & ~Copyable>(_ polynomial: ExactPolynomial<ExactRationalScalarDomain>,
        at parameter: OriginalPhysicalAngleInterval,_ a: inout A) throws -> OriginalPhysicalAngleInterval {
        var total = OriginalPhysicalAngleInterval(try owner.rationals.integer(0,using:&a))
        for term in polynomial.terms {
            try a.consumeWork(1)
            total = try total.adding(parameter.powered(term.powers[0],owner.rationals,&a)
                .multiplying(.init(term.coefficient),owner.rationals,&a),owner.rationals,&a)
        }
        return total
    }
}
