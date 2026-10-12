#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain: ExactPolynomialOrderedConstructing {
    public func polynomial<A: ExactScalarAdmission & ~Copyable>(
        orderedTerms: [ExactPolynomialTerm<Coefficient>], using admission: inout A
    ) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission) { usage in
            for index in orderedTerms.indices {
                let term = orderedTerms[index]
                try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
                guard term.powers.count == variableCount else { throw ExactPolynomialFailure.invalidExponent }
                for exponent in term.powers {
                    guard exponent >= 0 else { throw ExactPolynomialFailure.invalidExponent }
                }
                guard try field.sign(of: term.coefficient, using: &usage) != .zero else {
                    throw ExactPolynomialFailure.invalidCertificate
                }
                if index > 0 {
                    guard try ExactPolynomialAccess.order(orderedTerms[index - 1].powers, term.powers, &usage) > 0 else {
                        throw ExactPolynomialFailure.invalidCertificate
                    }
                }
            }
            return try wrap(orderedTerms, &usage)
        }
    }
}
