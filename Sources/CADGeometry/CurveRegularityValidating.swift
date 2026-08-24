import CADCore

/// Certifies that a curve parameterization has a non-degenerate tangent
/// throughout a bounded parameter interval.
public protocol CurveRegularityValidating: Sendable {
    func validate(
        _ curve: Curve3D,
        over parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws
}
