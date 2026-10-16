import CADCore

/// One admitted original support pair reused across selected closed box queries.
public protocol OriginalSurfacePairIntersecting: Sendable {
    var firstSurface: Surface3D { get }
    var secondSurface: Surface3D { get }
    var tolerance: ModelingTolerance { get }
    func admitsFirstOrderContinuity(over box: SurfaceParameterBox) throws -> Bool
    func admitsFirstOrderContinuity(over box: SurfaceParameterBox,
        using execution: inout OriginalQueryExecution) throws -> Bool
    func firstDifferentialEnclosure(over box: SurfaceParameterBox) throws -> SurfaceDifferentialEnclosure
    func firstDifferentialEnclosure(over box: SurfaceParameterBox,
        using execution: inout OriginalQueryExecution) throws -> SurfaceDifferentialEnclosure
    func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> SurfaceSurfaceIntersectionResult
    func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult
    func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> [SurfaceSurfaceIntersection]
    func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions,
        using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection]
}

public extension OriginalSurfacePairIntersecting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy custom pair sessions do not supply
    // same-execution continuity, differential or contact witnesses. Bounded embedding
    // consumers must receive explicit failure until these direct requirements are implemented.
    func admitsFirstOrderContinuity(over box: SurfaceParameterBox,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This original surface-pair session has no direct continuity witness.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy custom pair sessions need the actual
    // caller execution before their differential enclosure can serve bounded embedding.
    func firstDifferentialEnclosure(over box: SurfaceParameterBox,
        using execution: inout OriginalQueryExecution) throws -> SurfaceDifferentialEnclosure {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This original surface-pair session has no direct differential witness.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy custom rich sessions cannot establish
    // same-execution resource evidence by ordinary replay; direct publication must fail.
    func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions,
        using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This original surface-pair session has no direct rich result producer.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy custom array sessions need a direct
    // original contact witness before bounded embedding may publish their intersections.
    func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions,
        using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection] {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This original surface-pair session has no direct intersection producer.")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Custom sessions must implement retained
    // original rich coverage under their existing invocation before publication.
    func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions) throws -> SurfaceSurfaceIntersectionResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This original surface-pair session has no rich result producer.")
    }
}
