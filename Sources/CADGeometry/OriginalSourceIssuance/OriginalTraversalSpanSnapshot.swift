import CADCore

/// Keeps the actual directed source and exact original endpoint coefficients.
public struct OriginalTraversalSpanSnapshot<Child: Sendable>: OriginalTraversalSourceReading {
    public let original: OriginalCurveRootSpan3D
    public let originalChild: OriginalSourceBinding<Child>
    public let originalStart: OriginalExactScalar
    public let originalEnd: OriginalExactScalar
    public let field: OriginalExactScalarDomain
    init(original: OriginalCurveRootSpan3D, child: OriginalSourceBinding<Child>,
        start: OriginalExactScalar, end: OriginalExactScalar, field: OriginalExactScalarDomain) {
        self.original = original; originalChild = child; originalStart = start; originalEnd = end; self.field = field
    }
}
