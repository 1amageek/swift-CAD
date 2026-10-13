/// Selected original slant at a complete physical cosine zero.
public struct OriginalCertifiedSphereConePlaneRoot: Sendable {
    public typealias Base = OriginalPhysicalAngleScalarDomain
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public typealias Value = Field.Value
    public let phaseOrdinal: Int
    public let field: Field
    public let radical: Value
    public let slant: Value
    public let x: Value
    public let z: Value
    public let sine: Int
    public let proofDepth: ExactScalarDepth
    init(phaseOrdinal: Int, field: Field, radical: Value, slant: Value, x: Value, z: Value,
        sine: Int, proofDepth: ExactScalarDepth) {
        self.phaseOrdinal = phaseOrdinal; self.field = field; self.radical = radical
        self.slant = slant; self.x = x; self.z = z; self.sine = sine; self.proofDepth = proofDepth
    }
}
