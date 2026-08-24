import CADCore

package extension CertifiedImplicitSurfaceParameterCurve {
    func exactPlanarAffineFluxTraversal(
        on surface: BSplineSurface3D,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedPlanarAffineFluxTraversal? {
        guard let graph = try ExactIsoparametricPlanarIntersectionGraph.certified(
            first: intersection.firstSurface,
            second: intersection.secondSurface,
            tolerance: tolerance
        ) else {
            return nil
        }
        return try graph.planarAffineFluxTraversal(
            curve: self,
            surface: surface,
            reference: reference,
            tolerance: tolerance
        )
    }
}
