import CADCore

/// The actual construction and each directed boundary owner remain immutable.
public struct OriginalCoonsSurfaceSnapshot<Bottom: Sendable, Top: Sendable, Left: Sendable, Right: Sendable>: OriginalCoonsSourceReading {
    public let original: OriginalCoonsSurface3D
    public let bottomBoundary: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Bottom>>
    public let topBoundary: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Top>>
    public let leftBoundary: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Left>>
    public let rightBoundary: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Right>>
    public let field: OriginalExactScalarDomain
    init(original: OriginalCoonsSurface3D, bottom: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Bottom>>,
        top: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Top>>, left: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Left>>,
        right: OriginalSourceBinding<OriginalTraversalSpanSnapshot<Right>>, field: OriginalExactScalarDomain) {
        self.original = original; bottomBoundary = bottom; topBoundary = top
        leftBoundary = left; rightBoundary = right; self.field = field
    }
}
