import CADCore
import CADGeometry

/// Bounded final paper-point XY proposals with original directed algebraic source retained.
public struct OriginalRootSpanDrawingPath: Sendable {
    public struct Sample: Sendable {
        public let normalizedParameter: Double
        public let point: Point2D
    }
    public let span: OriginalCurveRootSpan3D
    public let operationWord: OriginalAffineOperationWord
    public let maximumDeviation: Double
    public let samples: [Sample]
    let accountingOwner: DrawingExchangeUsage
}
