import CADCore

/// One immutable owner retains complete descendant coverage for every parent graph.
public final class OriginalRollingBallSpatialWordCoverage: Sendable {
    public typealias Word=OriginalAffineWordSnapshot<OriginalAffineWordCurve3D,OriginalRollingBallCurveSnapshot>
    public typealias Children=OriginalCompleteCurveGraphs<OriginalRollingBallCurveSnapshot,OriginalRollingBallCurveGraphEvidence,OriginalRollingBallCurveGraphCoverage>
    public let source: OriginalSourceBinding<Word>
    public let children: Children
    init(source: OriginalSourceBinding<Word>,children: Children) { self.source=source;self.children=children }
}
