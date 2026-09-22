import CADCore

/// One minor circular section with correspondence to both source surfaces.
public struct RollingBallSection: Sendable {
    public let center: Point3D
    public let radius: Double
    public let firstContactParameter: SurfaceParameter
    public let secondContactParameter: SurfaceParameter
    public let firstContactPoint: Point3D
    public let secondContactPoint: Point3D
    public let arc: BSplineCurve3D
    /// Measured only at this section; not a bound over the entire spine.
    public let maximumContactResidual: Double
}
