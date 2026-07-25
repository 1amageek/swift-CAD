protocol CertifiedIntersectionPlaneReductionResolving: Sendable {
    func reduction(
        for curve: CertifiedIntersectionCurve3D
    ) -> CertifiedIntersectionPlaneReduction?
}
