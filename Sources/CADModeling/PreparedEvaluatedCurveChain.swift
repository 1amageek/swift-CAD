/// A reusable physical-distance parameterization for an ordered curve chain.
public struct PreparedEvaluatedCurveChain: Sendable {
    struct Segment: Sendable {
        let path: PreparedEvaluatedCurvePath
        let isReversed: Bool
        let startDistance: Double
        let endDistance: Double
    }

    public let totalLength: Double
    let segments: [Segment]

    init(
        totalLength: Double,
        segments: [Segment]
    ) {
        self.totalLength = totalLength
        self.segments = segments
    }
}
