import CADCore

struct DefaultBoundedBSplineSurfaceExactIntersectionResolver:
    BoundedBSplineSurfaceExactIntersectionResolving
{
    func certificate(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BoundedBSplineSurfaceExactIntersectionCertificate? {
        if first == second {
            return .coincidence
        }
        if let certificate = try QuadraticHeightFieldTangencyCertificate
            .certified(
                first: first,
                second: second,
                tolerance: tolerance
            ) {
            return .quadraticTangency(certificate)
        }
        if let certificate = try QuarticHeightFieldTangencyCertificate
            .certified(
                first: first,
                second: second,
                tolerance: tolerance
            ) {
            return .quarticTangency(certificate)
        }
        if let certificate = try ExactIsoparametricPlanarIntersectionGraph
            .certified(
                first: first,
                second: second,
                tolerance: tolerance
            ) {
            return .isoparametricPlanar(certificate)
        }
        if let certificate = try ExactAffineBilinearIntersectionGraph
            .certified(
                first: first,
                second: second,
                tolerance: tolerance
            ) {
            return .affineBilinear(certificate)
        }
        return nil
    }
}
