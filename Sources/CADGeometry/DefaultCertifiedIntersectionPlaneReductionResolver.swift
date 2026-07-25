struct DefaultCertifiedIntersectionPlaneReductionResolver:
    CertifiedIntersectionPlaneReductionResolving
{
    func reduction(
        for curve: CertifiedIntersectionCurve3D
    ) -> CertifiedIntersectionPlaneReduction? {
        switch curve {
        case let .sphereCone(curve):
            CertifiedIntersectionPlaneReduction(
                sectionSurface: curve.sphereSurface,
                remainingSurface: curve.coneSurface
            )
        case let .coneCone(curve):
            CertifiedIntersectionPlaneReduction(
                sectionSurface: curve.parameterizedSurface,
                remainingSurface: curve.referenceSurface
            )
        case let .coneCylinder(curve):
            CertifiedIntersectionPlaneReduction(
                sectionSurface: curve.cylinderSurface,
                remainingSurface: curve.coneSurface
            )
        case let .coneTorus(curve):
            CertifiedIntersectionPlaneReduction(
                sectionSurface: curve.coneSurface,
                remainingSurface: curve.torusSurface
            )
        case .parallelTorusTorus:
            nil
        }
    }
}
