#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain: ExactPolynomialSquareFreeProducing {
    public typealias SquareFreeDecomposition = ExactPolynomialSquareFreeDecomposition<F>
    public func squareFreeDecomposition<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> SquareFreeDecomposition {
        try query(&admission, copy value) { usage in
            guard let leading = value.terms.first else { throw ExactPolynomialFailure.undefinedMultiplicity }
            let original = try monic(value, &usage)
            var repeated = original
            for variable in 0..<variableCount {
                try usage.consumeWork(1)
                repeated = try gcd(repeated, differentiated(original, variable, &usage), &usage)
                if (try activeVariable(repeated, &usage)) == nil { break }
            }
            var remaining = try exactDivide(original, repeated, &usage)
            var factors: [ExactPolynomialSquareFreeFactor<F>] = []
            var multiplicity = 1
            while (try activeVariable(remaining, &usage)) != nil {
                let shared = try gcd(remaining, repeated, &usage)
                let factor = try exactDivide(remaining, shared, &usage)
                if (try activeVariable(factor, &usage)) != nil {
                    try ExactPolynomialAccess.storage(1, ExactPolynomialSquareFreeFactor<F>.self, &usage)
                    factors.append(.init(polynomial: factor, multiplicity: multiplicity))
                }
                remaining = shared; repeated = try exactDivide(repeated, shared, &usage)
                multiplicity = try ExactPolynomialAccess.count(multiplicity, 1)
            }
            guard (try activeVariable(repeated, &usage)) == nil else { throw ExactPolynomialFailure.invalidCertificate }
            try ExactPolynomialAccess.storage(factors.count, ExactPolynomialSquareFreeFactor<F>.self, &usage)
            var retained: [ExactPolynomialSquareFreeFactor<F>] = []; retained.reserveCapacity(factors.count)
            for factor in factors { retained.append(.init(polynomial: try wrap(factor.polynomial.terms, &usage), multiplicity: factor.multiplicity)) }
            return SquareFreeDecomposition(context: context, unit: leading.coefficient, factors: retained, depth: try usage.depth)
        }
    }
}
