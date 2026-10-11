import CADCore

/// Ordered original sources and the final field retaining every earlier ancestor.
public struct OriginalPreparedPolylinePcurves: Sendable {
    public let sources: [OriginalSourceBinding<OriginalPolylinePcurveSnapshot>]
    public let field: OriginalExactScalarDomain
    init(sources: [OriginalSourceBinding<OriginalPolylinePcurveSnapshot>],field: OriginalExactScalarDomain) {
        self.sources=sources;self.field=field
    }
}
