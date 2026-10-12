#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactAlgebraicScalarDomain {
    /// Issues an inverse only when exact Euclidean evidence proves a unit modulo the retained law.
    func unitInverse(_ denominator: ExactPolynomial<Self>, modulo law: ExactPolynomial<Self>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactPolynomial<Self>? {
        guard let root = context.root, let parentContext = context.parent else {
            throw ExactScalarFailure.invalidEvidence
        }
        let p = root.source.context.univariate, parent = Self(context: parentContext)
        let one = try p.constant(parent.integer(1, using: &a), using: &a)
        var first = law, second = denominator
        var firstCoefficient = try p.constant(parent.integer(0, using: &a), using: &a)
        var secondCoefficient = one
        while try !p.isZero(second, using: &a) {
            try a.consumeWork(1)
            let division = try p.divided(first, by: second, using: &a)
            let nextCoefficient = try p.subtracting(firstCoefficient,
                p.multiplying(division.quotient, secondCoefficient, using: &a), using: &a)
            first = second; second = division.remainder
            firstCoefficient = secondCoefficient; secondCoefficient = nextCoefficient
        }
        guard try p.degree(of: first, in: 0, using: &a) == 0, let constant = first.terms.first else {
            return nil
        }
        let scale = try parent.dividing(parent.integer(1, using: &a), constant.coefficient, using: &a)
        let inverse = try p.divided(p.scaled(firstCoefficient, by: scale, using: &a), by: law, using: &a).remainder
        let identity = try p.subtracting(p.multiplying(denominator, inverse, using: &a), one, using: &a)
        guard try p.isZero(p.divided(identity, by: law, using: &a).remainder, using: &a) else {
            throw ExactScalarFailure.invalidEvidence
        }
        return inverse
    }
}
