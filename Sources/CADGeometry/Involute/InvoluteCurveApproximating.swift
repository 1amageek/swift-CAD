import CADCore

public protocol InvoluteCurveApproximating: Sendable {
    func approximate(baseRadius: Double, rollRange: ClosedRange<Double>,
        maximumError: Double, maximumSegments: Int,
        tolerance: ModelingTolerance) throws -> InvoluteApproximation
}
