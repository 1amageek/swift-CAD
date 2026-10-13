/// Exact intrinsic latitude B/(2*pi)*asin(z/3), with its canonical branch.
public struct OriginalCertifiedSphereConeLatitude: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let labelPeriod: Field.Value
    public let source: OriginalSourceBinding<OriginalCertifiedSphereConeFullSnapshot>
    public let phaseOrdinal: Int
    public let proofDepth: ExactScalarDepth

    private init(field: Field, sine: Field.Value, cosine: Field.Value,
        labelPeriod: Field.Value, source: OriginalSourceBinding<OriginalCertifiedSphereConeFullSnapshot>,
        phaseOrdinal: Int, proofDepth: ExactScalarDepth) {
        self.field = field; self.sine = sine; self.cosine = cosine; self.labelPeriod = labelPeriod
        self.source = source; self.phaseOrdinal = phaseOrdinal; self.proofDepth = proofDepth
    }
    public static func issue<A: ExactScalarAdmission & ~Copyable>(
        source: OriginalSourceBinding<OriginalCertifiedSphereConeFullSnapshot>, phaseOrdinal: Int,
        limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> OriginalCertifiedSphereConeLatitude {
        try a.checkpoint(); try source.require(limits)
        guard phaseOrdinal >= 0, phaseOrdinal < source.original.roots.count else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        let root = source.original.roots[phaseOrdinal], f = root.field
        let three = try f.integer(3, using: &a)
        let sine = try f.dividing(root.z, three, using: &a)
        // The whole-source pole-free theorem and positive slant select this sign.
        // At the first phase only the positive full branch has negative X.
        let negativeX = phaseOrdinal == 0 && source.original.original.componentKind == .positiveFullBranch
        let absoluteX = negativeX ? try f.negated(root.x, using: &a) : root.x
        let cosine = try f.dividing(absoluteX, three, using: &a)
        let period = try f.binary64(exactly: 2 * Double.pi, using: &a)
        let depth = try ExactScalarDepth(value: max(root.proofDepth.value, sine.depth.value, cosine.depth.value),
            coefficient: max(root.proofDepth.coefficient, sine.depth.coefficient, cosine.depth.coefficient))
        try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCertifiedSphereConeLatitude.self))
        let result = OriginalCertifiedSphereConeLatitude(field: f, sine: sine, cosine: cosine,
            labelPeriod: period, source: source, phaseOrdinal: phaseOrdinal, proofDepth: depth)
        try a.checkpoint(); return result
    }
}
