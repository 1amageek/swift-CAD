import CADCore

/// Exact original two-angle coordinate; its numerator and denominator owners stay distinct.
public struct OriginalConeConeSurfaceCoordinate: Sendable {
    public typealias Field = OriginalFullConeConeSurfaceSnapshot.Field
    public enum Kind: Sendable { case parameterizedSlant, referenceSlant, x, y, z }
    public enum ReferenceFactor: Sendable { case one, sine, cosine }
    public struct Definition: Sendable {
        public let coordinate: OriginalConeConeSurfaceCoordinate
        public let numeratorReferenceFactor: ReferenceFactor
        public let numeratorParameterizedFactor: Field.Value
        public let denominatorReferenceCosineFactor: Field.Value
        public let denominatorReferenceSineFactor: Field.Value
    }
    public let source: OriginalSourceBinding<OriginalFullConeConeSurfaceSnapshot>
    public let values: OriginalConeConeSurfaceSectionValues
    public let branch: Int
    public let kind: Kind
    public let proofDepth: ExactScalarDepth
    private init(source: OriginalSourceBinding<OriginalFullConeConeSurfaceSnapshot>, values: OriginalConeConeSurfaceSectionValues,
        branch: Int, kind: Kind, proofDepth: ExactScalarDepth) {
        self.source = source; self.values = values; self.branch = branch; self.kind = kind; self.proofDepth = proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits, using a: inout A) throws {
        try a.checkpoint(); try source.require(limits); try source.original.admitProof(using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        _ = try values.field.importing(source.original.parameterizedSine, using: &a)
        _ = try values.field.importing(source.original.parameterizedCosine, using: &a)
        try a.checkpoint()
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<OriginalFullConeConeSurfaceSnapshot>,
        values: OriginalConeConeSurfaceSectionValues, branch: Int, kind: Kind, limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws -> Self {
        try source.require(limits); try source.original.admitProof(using: &a)
        try a.admitDepth(value: values.proofDepth.value, coefficient: values.proofDepth.coefficient)
        guard branch == 0 || branch == 1 else { throw OriginalSourceIssuanceFailure.invalidChart }
        _ = try values.field.importing(source.original.parameterizedSine, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let result = Self(source: source, values: values, branch: branch, kind: kind, proofDepth: values.proofDepth)
        try a.checkpoint(); return result
    }
    /// Coordinate = referenceFactor(alpha)*numeratorBeta /
    /// (cos(alpha)*denominatorCosBeta + sin(alpha)*denominatorSinBeta).
    public func definition<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws -> Definition {
        try admitProof(limits: limits, using: &a)
        let f = values.field, sign = branch == 0 ? 1 : -1
        let denominatorSine = try f.multiplying(f.integer(sign, using: &a),
            f.multiplying(values.parameterizedSine, values.cosine, using: &a), using: &a)
        let factor: ReferenceFactor, numerator: Field.Value
        switch kind {
        case .parameterizedSlant:
            factor = .sine; numerator = try f.integer(sign * 4, using: &a)
        case .referenceSlant:
            factor = .one; numerator = try f.multiplying(f.integer(4, using: &a), values.radialRoot, using: &a)
        case .x:
            factor = .sine; numerator = try f.multiplying(f.integer(-sign * 4, using: &a),
                f.multiplying(values.parameterizedSine, values.sine, using: &a), using: &a)
        case .y:
            factor = .sine; numerator = try f.multiplying(f.integer(sign * 4, using: &a), values.parameterizedCosine, using: &a)
        case .z:
            factor = .cosine; numerator = try f.multiplying(f.integer(4, using: &a), values.radialRoot, using: &a)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Definition.self))
        let result = Definition(coordinate: self, numeratorReferenceFactor: factor, numeratorParameterizedFactor: numerator,
            denominatorReferenceCosineFactor: values.radialRoot, denominatorReferenceSineFactor: denominatorSine)
        try a.checkpoint(); return result
    }
    public func sign<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws -> ExactSign {
        let d = try definition(limits: limits, using: &a)
        // The source theorem proves both denominators and each alpha factor positive.
        return try values.field.sign(of: d.numeratorParameterizedFactor, using: &a)
    }
}
