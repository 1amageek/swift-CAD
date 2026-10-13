import CADCore

/// A sealed original two-angle ratio with source-selected phase and root sign.
public struct OriginalCertifiedConeConeCoordinate: Sendable {
    public enum Kind: Sendable { case parameterizedSlant, referenceSlant, planeU, planeV }
    public let source: OriginalSourceBinding<OriginalCertifiedConeConeFullSnapshot>
    public let phaseOrdinal: Int
    public let kind: Kind
    public var proofDepth: ExactScalarDepth { source.original.proofDepth }
    private init(source: OriginalSourceBinding<OriginalCertifiedConeConeFullSnapshot>,
        phaseOrdinal: Int, kind: Kind) { self.source = source; self.phaseOrdinal = phaseOrdinal; self.kind = kind }
    static func issue<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<OriginalCertifiedConeConeFullSnapshot>,
        phaseOrdinal: Int, kind: Kind, limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> Self {
        try source.require(limits); try source.original.admitProof(using: &a)
        guard phaseOrdinal >= 0, phaseOrdinal < 2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let result = Self(source: source, phaseOrdinal: phaseOrdinal, kind: kind); try a.checkpoint(); return result
    }
    public func bounds<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        tolerance: ModelingTolerance, using a: inout A) throws -> ScalarInterval {
        try source.require(limits)
        let value = try source.original.bounds(phaseOrdinal: phaseOrdinal, tolerance: tolerance, using: &a)
        let bound: OutwardScalarInterval
        switch kind { case .parameterizedSlant: bound = value.parameterizedSlant
        case .referenceSlant: bound = value.referenceSlant; case .planeU: bound = value.planeU; case .planeV: bound = value.planeV }
        return try .init(lower: bound.lower, upper: bound.upper)
    }
}
