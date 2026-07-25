protocol CertifiedIntersectionReductionResolving: Sendable {
    func reduction(
        for curve: CertifiedIntersectionCurve3D
    ) -> CertifiedIntersectionReduction?
}
