protocol CertifiedIntersectionCoincidenceResolving: Sendable {
    func isSourceSurface(
        _ surface: Surface3D,
        of curve: CertifiedIntersectionCurve3D
    ) -> Bool
}
