/// Exact original rational surface partials in the selected native UV chart.
package struct OriginalRationalSurfaceDerivativeLaw: Sendable {
    package typealias Partial = OriginalRationalVectorDerivativeLaw.Partial
    package let original: OriginalRationalSurfacePolynomial
    package var partials: [Partial] { vector.partials }
    private let vector: OriginalRationalVectorDerivativeLaw

    package init<B: RationalAlgebraAdmitting>(original: OriginalRationalSurfacePolynomial,
        throughOrder: Int, usage: inout B) throws {
        self.original = original
        vector = try OriginalRationalVectorDerivativeLaw(homogeneous: original.homogeneous,
            throughOrder: throughOrder, usage: &usage)
    }

    package func equalityNumerators<B: RationalAlgebraAdmitting>(with other: Self,
        secondTranslation: (alongU: Bool, amount: ExactRationalCoefficient)? = nil,
        requiredPartials: [(uOrder: Int, vOrder: Int)]? = nil,
        usage: inout B) throws -> [ExactBivariatePolynomial] {
        try vector.equalityNumerators(with: other.vector, secondTranslation: secondTranslation, requiredPartials: requiredPartials, usage: &usage)
    }
}
