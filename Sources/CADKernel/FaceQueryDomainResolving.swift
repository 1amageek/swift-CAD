import CADCore
import CADGeometry
import CADTopology

protocol FaceQueryDomainResolving: Sendable {
    func makeContainmentSession(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FaceParameterContainmentSession

    func closestBoundaryProjection(
        to point: Point3D,
        from supportParameter: SurfaceParameter,
        on faceID: FaceID,
        surface: Surface3D,
        in model: BRepModel,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> FaceTrimBoundaryProjection

    func directionalSearchDomain(
        from origin: Point3D,
        direction: Vector3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceDirectionalSearchDomain
}
