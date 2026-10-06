/// Original stationary curve incidence, distinct from an isolated zero contact.
public struct SurfaceSilhouetteSingularStation: Sendable {
    public enum Kind: Sendable { case cusp }
    public let branchMultiplicity: Int
    public let characteristicExponent: Int
    public let retainedHalfBranchCount: Int
    public let curveIndex: Int
    public let kind: Kind
    public let curveParameterEnclosure: ScalarInterval
    public let originalU: ExactRationalCoefficient
    public let originalV: ExactRationalCoefficient
    public let originalParameterEnclosure: SurfaceParameterBox
    public let spatialEnclosure: CoordinateEnclosure3D
    let originalCurve: OriginalSurfaceSilhouetteCurve
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        usage: inout SurfaceSilhouetteUsage) throws {
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.write(self, usage: &usage)
    }

}
