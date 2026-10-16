import CADCore
import CADGeometry
import CADTopology

protocol FaceQueryDomainResolving: Sendable {
    func makeContainmentSession(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FaceParameterContainmentSession

    func makeContainmentSession(for faceID: FaceID, in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> any FaceParameterContainmentSession

    func closestBoundaryProjection(
        to point: Point3D,
        from supportParameter: SurfaceParameter,
        on faceID: FaceID,
        surface: Surface3D,
        in model: BRepModel,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> FaceTrimBoundaryProjection

    func closestBoundaryProjection(to point: Point3D, from supportParameter: SurfaceParameter,
        on faceID: FaceID, surface: Surface3D, in model: BRepModel,
        maximumIterations: Int, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> FaceTrimBoundaryProjection

    func directionalSearchDomain(
        from origin: Point3D,
        direction: Vector3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceDirectionalSearchDomain

    func directionalSearchDomain(from origin: Point3D, direction: Vector3D,
        on faceID: FaceID, in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> FaceDirectionalSearchDomain
}

extension FaceQueryDomainResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected directional domain providers must
    // implement caller-owned admission before SurfaceQueryEvaluator.project can use them.
    // Ordinary dispatch cannot establish this direct execution contract.
    func directionalSearchDomain(from origin: Point3D, direction: Vector3D,
        on faceID: FaceID, in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> FaceDirectionalSearchDomain {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "The directional domain provider has no direct original execution witness.")
    }

    func makeContainmentSession(for faceID: FaceID, in model: BRepModel,
        tolerance: ModelingTolerance) throws -> any FaceParameterContainmentSession {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try makeContainmentSession(for: faceID, in: model, tolerance: tolerance, using: &execution)
    }

    func closestBoundaryProjection(to point: Point3D, from supportParameter: SurfaceParameter,
        on faceID: FaceID, surface: Surface3D, in model: BRepModel,
        maximumIterations: Int, tolerance: ModelingTolerance) throws -> FaceTrimBoundaryProjection {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try closestBoundaryProjection(to: point, from: supportParameter, on: faceID,
            surface: surface, in: model, maximumIterations: maximumIterations,
            tolerance: tolerance, using: &execution)
    }
}
