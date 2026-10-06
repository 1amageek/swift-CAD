/// Producer-created candidate published only with whole-law position evidence.
public struct CertifiedPolynomialSurfaceContinuationCandidate: Sendable {
    public let surface: BSplineSurface3D
    public let certificate: NativeSurfacePositionCertificate

    init(surface: BSplineSurface3D, certificate: NativeSurfacePositionCertificate) {
        self.surface = surface
        self.certificate = certificate
    }
}
