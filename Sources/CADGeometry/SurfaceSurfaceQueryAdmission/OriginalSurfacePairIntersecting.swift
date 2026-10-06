import CADCore

/// One admitted original support pair reused across selected closed box queries.
public protocol OriginalSurfacePairIntersecting: Sendable {
    var firstSurface: Surface3D { get }
    var secondSurface: Surface3D { get }
    var tolerance: ModelingTolerance { get }
    func admitsFirstOrderContinuity(over box: SurfaceParameterBox) throws -> Bool
    func firstDifferentialEnclosure(over box: SurfaceParameterBox) throws -> SurfaceDifferentialEnclosure
    func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> SurfaceSurfaceIntersectionResult
    func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> [SurfaceSurfaceIntersection]
}

public extension OriginalSurfacePairIntersecting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Custom sessions must implement retained
    // original rich coverage under their existing invocation before publication.
    func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> SurfaceSurfaceIntersectionResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This original surface-pair session has no rich result producer.")
    }
}
