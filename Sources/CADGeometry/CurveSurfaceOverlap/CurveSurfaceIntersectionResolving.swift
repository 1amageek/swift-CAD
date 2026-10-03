import CADCore

/// Returns complete isolated intersections and certified continuous overlap intervals.
/// Unresolved membership or incomplete clipping must fail instead of returning a partial set.
public protocol CurveSurfaceIntersectionResolving: Sendable {
    func intersectionResult(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersectionResult
}
