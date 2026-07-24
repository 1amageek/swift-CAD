import CADCore

protocol BoundedBSplineSurfaceExactIntersectionResolving {
    func certificate(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BoundedBSplineSurfaceExactIntersectionCertificate?
}
