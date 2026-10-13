import CADCore

/// Whole original full-branch support and both selected plane-contact radicals.
public struct OriginalCertifiedSphereConeFullSnapshot: Sendable {
    public let original: CertifiedSphereConeIntersectionCurve
    public let physical: OriginalPhysicalAngleScalarDomain
    public let phase: OriginalAnalyticCosineZeroReceipt<OriginalCertifiedSphereConePhase, OriginalPiScalarDomain>
    public let roots: [OriginalCertifiedSphereConePlaneRoot]
    public let proofDepth: ExactScalarDepth
    init(original: CertifiedSphereConeIntersectionCurve, physical: OriginalPhysicalAngleScalarDomain,
        phase: OriginalAnalyticCosineZeroReceipt<OriginalCertifiedSphereConePhase, OriginalPiScalarDomain>,
        roots: [OriginalCertifiedSphereConePlaneRoot], proofDepth: ExactScalarDepth) {
        self.original = original; self.physical = physical; self.phase = phase
        self.roots = roots; self.proofDepth = proofDepth
    }
}
