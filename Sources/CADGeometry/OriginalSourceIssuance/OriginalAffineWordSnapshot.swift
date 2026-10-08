import CADCore

/// Retains the authored image, exact word coefficients and its descendant owner.
public struct OriginalAffineWordSnapshot<Original: Sendable, Child: Sendable>: OriginalSpatialSourceReading {
    public let original: Original
    public let originalChild: OriginalSourceBinding<Child>
    public let field: OriginalExactScalarDomain
    private let coefficients: [OriginalExactScalar]
    init(original: Original, child: OriginalSourceBinding<Child>, field: OriginalExactScalarDomain,
        coefficients: [OriginalExactScalar]) {
        self.original = original; originalChild = child; self.field = field; self.coefficients = coefficients
    }
    public func spatialCoefficient(row: Int, column: Int) -> OriginalExactScalar {
        coefficients[row * 4 + column]
    }
}
