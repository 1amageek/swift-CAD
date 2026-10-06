import CADCore

/// A source point and its verified target coordinates.
public struct CurveSurfaceOverlapEndpoint: Sendable, Equatable {
    public let curveParameter: Double
    public let point: Point3D
    public let surfaceParameter: SurfaceParameter
    public let residual: Double
    /// U is nonunique at a pole or apex; the returned coordinates still represent the point.
    public let isSurfaceChartSingular: Bool
}
