import CADCore

/// Original complete-range derivatives, including the third Taylor remainder.
package protocol GeometryCurveDerivativeEnclosing: Sendable {
    func derivatives(over parameters: ScalarInterval,
        tolerance: ModelingTolerance) throws -> IntervalVectorDerivativeJet
}
