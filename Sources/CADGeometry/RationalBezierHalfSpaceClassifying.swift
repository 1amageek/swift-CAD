import CADCore

public protocol RationalBezierHalfSpaceClassifying: Sendable {
    func classify(
        controlValues: [Double],
        weights: [Double],
        nonnegativeMargin: Double,
        tolerance: ModelingTolerance
    ) throws -> RationalBezierHalfSpaceClassification
}
