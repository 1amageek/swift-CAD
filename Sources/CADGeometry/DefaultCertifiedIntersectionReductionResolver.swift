struct DefaultCertifiedIntersectionReductionResolver:
    CertifiedIntersectionReductionResolving
{
    func reduction(
        for curve: CertifiedIntersectionCurve3D
    ) -> CertifiedIntersectionReduction? {
        switch curve {
        case let .sphereCone(curve):
            CertifiedIntersectionReduction(
                sectionSurface: curve.sphereSurface,
                remainingSurface: curve.coneSurface
            )
        case let .coneCone(curve):
            CertifiedIntersectionReduction(
                sectionSurface: curve.parameterizedSurface,
                remainingSurface: curve.referenceSurface
            )
        case let .coneCylinder(curve):
            CertifiedIntersectionReduction(
                sectionSurface: curve.cylinderSurface,
                remainingSurface: curve.coneSurface
            )
        case let .coneTorus(curve):
            CertifiedIntersectionReduction(
                sectionSurface: curve.coneSurface,
                remainingSurface: curve.torusSurface
            )
        case .parallelTorusTorus:
            nil
        }
    }
}
