#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension OriginalPhysicalAngleScalarDomain {
    public func sign<A: ExactScalarAdmission & ~Copyable>(of input: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactSign {
        let x = copy input
        return try Self.query(&admission) { a in
            try require(x, &a)
            if try owner.ring.isZero(x.numerator, using: &a) { return .zero }
            // Rational constants need neither transcendental intervals nor root visits.
            if x.numerator.terms.count == 1, x.denominator.terms.count == 1,
                x.numerator.terms[0].powers[0] == 0, x.denominator.terms[0].powers[0] == 0 {
                let n = try owner.rationals.sign(of: x.numerator.terms[0].coefficient, using: &a)
                let d = try owner.rationals.sign(of: x.denominator.terms[0].coefficient, using: &a)
                return n == d ? .positive : .negative
            }
            var refinement = try OriginalPhysicalAngleRefinement(owner, &a)
            while true {
                try a.checkpoint()
                guard let parameter = try refinement.next(&a) else { continue }
                guard let n = try enclosed(x.numerator, at: parameter, &a).sign(owner.rationals, &a),
                    let d = try enclosed(x.denominator, at: parameter, &a).sign(owner.rationals, &a) else { continue }
                return n == d ? .positive : .negative
            }
        }
    }
    func enclosed<A: ExactScalarAdmission & ~Copyable>(_ polynomial: ExactPolynomial<ExactRationalScalarDomain>,
        at parameter: OriginalPhysicalAngleInterval, _ a: inout A) throws -> OriginalPhysicalAngleInterval {
        var total = OriginalPhysicalAngleInterval(try owner.rationals.integer(0, using: &a))
        for term in polynomial.terms {
            try a.consumeWork(1)
            let power = try parameter.powered(term.powers[0], owner.rationals, &a)
            total = try total.adding(power.multiplying(.init(term.coefficient), owner.rationals, &a), owner.rationals, &a)
        }
        return total
    }
}
