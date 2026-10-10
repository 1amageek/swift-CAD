import CADCore

/// One immutable owner retains the map and complete original child family.
public final class OriginalRollingBallParameterImageCoverage: Sendable {
    public typealias Map=OriginalParameterImageSnapshot<ParameterImageCurve3D,OriginalRollingBallCurveSnapshot>
    public typealias Children=OriginalFiniteCurveGraphs<OriginalRollingBallCurveSnapshot,OriginalRollingBallCurveGraphEvidence,OriginalRollingBallCurveGraphCoverage>
    public let source: OriginalSourceBinding<Map>
    public let children: Children
    init(source: OriginalSourceBinding<Map>,children: Children) { self.source=source;self.children=children }
}
