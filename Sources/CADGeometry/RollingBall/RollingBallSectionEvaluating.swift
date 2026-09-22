import CADCore

/// Evaluates a local contact section, not a complete fillet surface or solid.
public protocol RollingBallSectionEvaluating: Sendable {
    func section(atCurveParameter parameter: Double) throws -> RollingBallSection
}
