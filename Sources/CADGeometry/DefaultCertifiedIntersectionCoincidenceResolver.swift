struct DefaultCertifiedIntersectionCoincidenceResolver:
    CertifiedIntersectionCoincidenceResolving
{
    func isSourceSurface(
        _ surface: Surface3D,
        of curve: CertifiedIntersectionCurve3D
    ) -> Bool {
        switch curve {
        case let .sphereCone(curve):
            surface == curve.sphereSurface || surface == curve.coneSurface
        case let .coneCone(curve):
            surface == curve.referenceSurface
                || surface == curve.parameterizedSurface
        case let .coneCylinder(curve):
            surface == curve.coneSurface || surface == curve.cylinderSurface
        case let .coneTorus(curve):
            surface == curve.coneSurface || surface == curve.torusSurface
        case let .parallelTorusTorus(curve):
            surface == curve.primarySurface || surface == curve.secondarySurface
        }
    }
}
