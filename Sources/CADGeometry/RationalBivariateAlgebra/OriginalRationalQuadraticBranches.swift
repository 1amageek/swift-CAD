import CADCore

/// Complete original quadratic real locus as two exact regular polynomial graphs.
package struct OriginalRationalQuadraticBranches: Sendable {
    package let original: ExactBivariatePolynomial
    package let freeAlongU: Bool
    package let first: ExactBivariatePolynomial
    package let second: ExactBivariatePolynomial
    package let originalBranchDifference: ExactBivariatePolynomial

    package static func proven<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        for alongU in [true, false] {
            let oriented = alongU ? original : try original.exchangedAxes(usage: &usage)
            guard oriented.vDegree == 2 else { continue }
            let quadratic = try oriented.coefficient(ofV: 2, usage: &usage)
            guard quadratic.uDegree == 0, let a = quadratic.leading?.value else { continue }
            let b = try oriented.coefficient(ofV: 1, usage: &usage)
            let c = try oriented.coefficient(ofV: 0, usage: &usage)
            let two = try ExactRationalCoefficient.natural(2, usage: &usage)
            let four = try two.multiplied(by: two, usage: &usage)
            let discriminant = try b.multiplied(by: b, usage: &usage)
                .subtracting(c.scaled(by: a.multiplied(by: four, usage: &usage), usage: &usage), usage: &usage)
            guard let square = try discriminant.exactSquareRoot(usage: &usage), !square.isZero else { continue }
            let reciprocal = try ExactRationalCoefficient.one.divided(by: a.multiplied(by: two, usage: &usage), usage: &usage)
            let coordinate = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
            let first = try coordinate.adding(b.subtracting(square, usage: &usage).scaled(by: reciprocal, usage: &usage), usage: &usage)
            let second = try coordinate.adding(b.adding(square, usage: &usage).scaled(by: reciprocal, usage: &usage), usage: &usage)
            guard try first.multiplied(by: second, usage: &usage).scaled(by: a, usage: &usage)
                .subtracting(oriented, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Original quadratic branches failed the complete original coefficient identity.")
            }
            return try Self(original: original, freeAlongU: alongU,
                first: alongU ? first : first.exchangedAxes(usage: &usage),
                second: alongU ? second : second.exchangedAxes(usage: &usage),
                originalBranchDifference: square)
        }
        return nil
    }

    package func stations<B: ExactScalarAdmission & ~Copyable>(over interval: ScalarInterval,
        maximumDepth: Int, usage: inout B) throws -> [ExactMonotoneGraphEndpoint] {
        let isolations = try ExactUnivariateRootIsolator().isolate(originalBranchDifference,
            lower: .originalDouble(interval.lower, usage: &usage),
            upper: .originalDouble(interval.upper, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        var result: [ExactMonotoneGraphEndpoint] = []
        for isolation in isolations {
            try RationalAlgebraStorage.retain(1, of: ExactMonotoneGraphEndpoint.self, usage: &usage)
            result.append(try .algebraic(ExactAlgebraicRealRoot(polynomial: originalBranchDifference,
                isolation: isolation, usage: &usage)))
        }
        return result
    }
}
