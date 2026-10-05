import CADCore

/// Retains the exact equivalence between original and square-free zero laws.
package struct OriginalRationalZeroSetAuthority: Sendable {
    package let original: ExactBivariatePolynomial
    package let repeatedFactor: ExactBivariatePolynomial
    private let derivatives: [[ExactBivariatePolynomial]]
    package let squareFree: ExactBivariatePolynomial

    package init<B: RationalAlgebraAdmitting>(original: ExactBivariatePolynomial,
        usage: inout B) throws {
        self.original = original
        if original.isZero {
            repeatedFactor = .zero; squareFree = .zero; derivatives = []; return
        }
        let u = try original.differentiated(alongU: true, usage: &usage)
        let v = try original.differentiated(alongU: false, usage: &usage)
        let producer = ExactBivariateGCD()
        let first = try producer.greatestCommonDivisor(original, u, usage: &usage)
        repeatedFactor = try producer.greatestCommonDivisor(first, v, usage: &usage)
        squareFree = try original.dividedExactly(by: repeatedFactor, usage: &usage).normalized(usage: &usage)
        let derivativeU = try squareFree.differentiated(alongU: true, usage: &usage)
        let derivativeV = try squareFree.differentiated(alongU: false, usage: &usage)
        let remaining = try producer.greatestCommonDivisor(
            producer.greatestCommonDivisor(squareFree, derivativeU, usage: &usage),
            derivativeV, usage: &usage)
        guard remaining.uDegree == 0, remaining.vDegree == 0 else {
            throw rationalAlgebraFailure("Original rational square-free zero authority has an unresolved repeated factor.")
        }
        derivatives = try Self.prepareDerivatives(squareFree, usage: &usage)
    }

    package func scalarJet<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        usage: inout B) throws -> OriginalRationalScalarDerivativeBounds {
        func value(_ u: Int, _ v: Int) throws -> OutwardScalarInterval {
            if squareFree.isZero { return .exact(0) }
            return try derivatives[u + v][u].enclosure(over: box, usage: &usage)
        }
        return try OriginalRationalScalarDerivativeBounds(value: value(0, 0), u: value(1, 0), v: value(0, 1),
            uu: value(2, 0), uv: value(1, 1), vv: value(0, 2),
            uuu: value(3, 0), uuv: value(2, 1), uvv: value(1, 2), vvv: value(0, 3))
    }

    private static func prepareDerivatives<B: RationalAlgebraAdmitting>(
        _ squareFree: ExactBivariatePolynomial, usage: inout B) throws -> [[ExactBivariatePolynomial]] {
        var derivatives: [[ExactBivariatePolynomial]] = []
        try RationalAlgebraStorage.retain(4, of: [ExactBivariatePolynomial].self, usage: &usage)
        derivatives.reserveCapacity(4)
        for total in 0...3 {
            try RationalAlgebraStorage.retain(total + 1, of: ExactBivariatePolynomial.self, usage: &usage)
            var row: [ExactBivariatePolynomial] = []; row.reserveCapacity(total + 1)
            for u in 0...total {
                var value = squareFree
                if u > 0 { for _ in 0..<u { value = try value.differentiated(alongU: true, usage: &usage) } }
                if total - u > 0 { for _ in 0..<(total - u) { value = try value.differentiated(alongU: false, usage: &usage) } }
                row.append(value)
            }
            derivatives.append(row)
        }
        return derivatives
    }
}
