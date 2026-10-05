/// One original outgoing half-edge at a retained exact span endpoint.
public struct OriginalPlanarCurveOutgoingGerm: Sendable {
    public let span: OriginalCurveRootSpan3D
    public let atStart: Bool

    public init(span: OriginalCurveRootSpan3D, atStart: Bool) {
        self.span = span; self.atStart = atStart
    }
}
