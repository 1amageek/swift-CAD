#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    func sourceForLaw<A: ExactScalarAdmission & ~Copyable>(_ law: ExactPolynomial<F>, variable: Int, axis: ExactScalarRootAxis,
        _ a: inout A) throws -> ExactRealRootSource<F> {
        _ = try context.univariate.isZero(law, using: &a)
        guard variable >= 0, variable < polynomials.variableCount else { throw ExactRealRootFailure.invalidVariable }
        try ExactRootAccess.storage(law.termCount, ExactPolynomialTerm<F.Value>.self, &a)
        var terms: [ExactPolynomialTerm<F.Value>] = []; terms.reserveCapacity(law.termCount)
        for term in law.terms {
            try a.consumeWork(polynomials.variableCount)
            try ExactRootAccess.storage(polynomials.variableCount, Int.self, &a)
            var powers = Array(repeating: 0, count: polynomials.variableCount)
            powers[variable] = term.powers[0]
            terms.append(.init(powers: powers, coefficient: term.coefficient))
        }
        let original = try polynomials.polynomial(terms: terms, using: &a)
        return .init(context: context, original: original, variable: variable,
            refinementAxis: axis, law: law, depth: (try a.depth))
    }
}
