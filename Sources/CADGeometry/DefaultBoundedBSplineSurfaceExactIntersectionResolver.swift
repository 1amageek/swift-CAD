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
        if let relation = ExactAffineBilinearIntersectionGraph.planeRelation(
            first: first,
            second: second
        ) {
            switch relation {
            case .coincident:
                return .coincidence
            case .disjoint:
                return .disjoint
            case .transverse:
                guard let intersection = try ExactAffineBilinearIntersectionGraph
                    .boundedAffineIntersection(
                        first: first,
                        second: second,
                        tolerance: tolerance
                    ) else {
                    break
                }
                switch intersection {
                case .disjoint:
                    return .disjoint
                case let .point(parameters):
                    return .affinePoint(parameters)
                case let .segment(graph):
                    return .affineBilinear(graph)
                }
            }
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
