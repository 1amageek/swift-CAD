/// Immutable residual contacts retaining every raw pair, scoped proof and lifted witness.
public struct OriginalIssuedGraphSelfContacts<S: Sendable,E: Sendable,C: Sendable,F: Sendable,D: Sendable>: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<OriginalExactScalarDomain>
    public let raw: OriginalIssuedGraphRelations<S,E,C,S,F,D>
    public let authoredDiagonals: [OriginalParameterIdentity<S,OriginalExactScalarDomain>]
    public let identities: [OriginalParameterIdentity<S,OriginalExactScalarDomain>]
    /// One retained refinement per raw pair, including complete empty refinements.
    public let refinements: [OriginalIssuedGraphParameterRefinement<S,E,C,S,F,D>]
    init(raw: OriginalIssuedGraphRelations<S,E,C,S,F,D>,
        authoredDiagonals: [OriginalParameterIdentity<S,OriginalExactScalarDomain>],
        identities: [OriginalParameterIdentity<S,OriginalExactScalarDomain>],
        refinements: [OriginalIssuedGraphParameterRefinement<S,E,C,S,F,D>]) {
        self.raw = raw; self.authoredDiagonals = authoredDiagonals
        self.identities = identities; self.refinements = refinements
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(pairOrdinal: Int,
        liftedCoordinates: [Field.Value], queryField: Field? = nil,
        domainLimits: OriginalDomainIdentityLimits, rootLimits: ExactRealRootLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            guard refinements.indices.contains(pairOrdinal) else { throw NativeExactRelationFailure.invalidDomain }
            let included = try refinements[pairOrdinal].contains(liftedCoordinates: liftedCoordinates,
                queryField: queryField, limits: domainLimits, rootLimits: rootLimits, using: &admission)
            try admission.checkpoint()
            return included
        } catch { throw .preserving(error) }
    }
}
