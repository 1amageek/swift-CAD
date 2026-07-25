struct DefaultCertifiedIntersectionReductionResolver:
    CertifiedIntersectionReductionResolving
{
    func reduction(
        for curve: CertifiedIntersectionCurve3D,
        target: CanonicalAnalyticSurface
    ) -> CertifiedIntersectionReduction? {
        switch (curve, target) {
        case let (.sphereCone(curve), .cylinder):
            CertifiedIntersectionReduction(
                sectionSurface: curve.coneSurface,
                remainingSurface: curve.sphereSurface
            )
        case let (.sphereCone(curve), _):
            CertifiedIntersectionReduction(
                sectionSurface: curve.sphereSurface,
                remainingSurface: curve.coneSurface
            )
        case let (.coneCone(curve), _):
            CertifiedIntersectionReduction(
                sectionSurface: curve.parameterizedSurface,
                remainingSurface: curve.referenceSurface
            )
        case let (.coneCylinder(curve), _):
            CertifiedIntersectionReduction(
                sectionSurface: curve.cylinderSurface,
                remainingSurface: curve.coneSurface
            )
        case let (.coneTorus(curve), _):
            CertifiedIntersectionReduction(
                sectionSurface: curve.coneSurface,
                remainingSurface: curve.torusSurface
            )
        case (.parallelTorusTorus, _):
            nil
        }
    }
}
