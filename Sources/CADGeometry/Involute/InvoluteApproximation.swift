public struct InvoluteApproximation: Sendable {
    public let spans: [BSplineCurve3D]
    public let positionErrorUpperBound: Double

    package init(spans: [BSplineCurve3D], positionErrorUpperBound: Double) {
        self.spans = spans
        self.positionErrorUpperBound = positionErrorUpperBound
    }
}
