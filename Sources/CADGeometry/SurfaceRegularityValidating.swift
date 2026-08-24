import CADCore

/// Certifies that a surface parameterization has a non-degenerate tangent
/// frame throughout a bounded parameter box.
public protocol SurfaceRegularityValidating: Sendable {
    func validate(
        _ surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws
}
