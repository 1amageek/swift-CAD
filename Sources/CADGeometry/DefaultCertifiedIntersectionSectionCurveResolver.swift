struct DefaultCertifiedIntersectionSectionCurveResolver:
    CertifiedIntersectionSectionCurveResolving
{
    func curve(
        for section: SurfaceSurfaceIntersectionCurve
    ) -> Curve3D {
        guard case let .analyticAnalytic(truth) = section.truth else {
            return section.curve
        }
        switch truth.definition {
        case let .sphereCone(curve):
            return .certifiedIntersection(.sphereCone(curve))
        case let .coneCone(curve):
            return .certifiedIntersection(.coneCone(curve))
        case let .coneCylinder(curve):
            return .certifiedIntersection(.coneCylinder(curve))
        case let .generalConeTorus(curve):
            return .certifiedIntersection(.coneTorus(curve))
        case let .parallelTorusTorus(curve):
            return .certifiedIntersection(.parallelTorusTorus(curve))
        case .planeTorus, .cylinderCylinder, .sphereCylinder, .sphereTorus,
             .parallelTorusCylinder, .generalTorusCylinder,
             .congruentTorusTorus, .generalTorusTorus, .boundedPlaneCone:
            return section.curve
        }
    }
}
