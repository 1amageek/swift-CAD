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
    func intersectionResult(curve: Curve3D, surface: Surface3D,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int?) throws -> CurveSurfaceIntersectionResult

}

public extension CurveSurfaceIntersectionResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Caller-admitted overlap consumers need
    // the conformer's actual original sector producer. Legacy private counters
    // cannot satisfy this bounded requirement.
    func intersectionResult(curve: Curve3D, surface: Surface3D,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> CurveSurfaceIntersectionResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Overlap conformer has no original caller-admitted sector producer.")
    }
}
