/// Original source ownership accompanying the composed equality predicate.
package struct OriginalRuledIntersectionRelation: Sendable {
    package enum Target: Sendable {
        case curve(OriginalRationalCurvePolynomial)
        case surface(OriginalRationalSurfacePolynomial)
    }
    package let ruled: OriginalRuledSurfacePolynomial
    package let target: Target
    package let relation: OriginalPolynomialRelation
}
