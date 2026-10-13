import CADCore

/// Whole original role lift and its exact directed child-parameter law.
public struct OriginalCertifiedPairLiftSnapshot: Sendable {
    public let original: SurfaceLiftCurve3D
    public let parameterCurve: CertifiedAnalyticPairSurfaceParameterCurve
    public let child: OriginalSourceBinding<OriginalCertifiedCoaxialConeCylinderSnapshot>
    public let start: OriginalPhysicalAngleValue
    public let end: OriginalPhysicalAngleValue
    public let extent: OriginalPhysicalAngleValue
    public let isConeRole: Bool
    public let proofDepth: ExactScalarDepth
}
