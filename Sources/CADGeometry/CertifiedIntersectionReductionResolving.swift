protocol CertifiedIntersectionReductionResolving: Sendable {
    func reduction(
        for curve: CertifiedIntersectionCurve3D,
        target: CanonicalAnalyticSurface
    ) -> CertifiedIntersectionReduction?
}
