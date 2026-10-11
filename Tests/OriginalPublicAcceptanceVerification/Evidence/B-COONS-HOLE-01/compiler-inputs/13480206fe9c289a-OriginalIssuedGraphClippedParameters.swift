/// Retains the original graph owners and the complete material refinement of every pair.
public struct OriginalIssuedGraphClippedParameters<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: Sendable {
    public let boundary: OriginalIssuedGraphBoundaryDomain<S, E, C, T, F, D>
    public let selection: OriginalNativeBoundaryDomain.Selection
    public let refinements: [OriginalIssuedGraphBoundaryRefinement<S, E, C, T, F, D>]

    init(boundary: OriginalIssuedGraphBoundaryDomain<S, E, C, T, F, D>, selection: OriginalNativeBoundaryDomain.Selection,
        refinements: [OriginalIssuedGraphBoundaryRefinement<S, E, C, T, F, D>]) {
        self.boundary = boundary
        self.selection = selection
        self.refinements = refinements
    }

    public func contains<A: ExactScalarAdmission & ~Copyable>(
        liftedCoordinates: [ExactAlgebraicScalarDomain<OriginalExactScalarDomain>.Value], pairOrdinal: Int,
        queryField: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>? = nil,
        limits: OriginalDomainIdentityLimits, rootLimits: ExactRealRootLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try a.checkpoint()
            try boundary.source.raw.admitProof(limits: limits, using: &a)
            guard refinements.indices.contains(pairOrdinal), refinements[pairOrdinal].parameters.pairOrdinal == pairOrdinal else {
                throw NativeExactRelationFailure.invalidDomain
            }
            let field = queryField ?? boundary.source.raw.first.field
            _ = try field.sign(of: boundary.source.raw.first.field.integer(0, using: &a), using: &a)
            for coordinate in liftedCoordinates { try a.consumeWork(1); _ = try field.sign(of: coordinate, using: &a) }
            let included = try refinements[pairOrdinal].parameters.contains(liftedCoordinates: liftedCoordinates,
                queryField: field, limits: limits, rootLimits: rootLimits, using: &a)
            try a.checkpoint()
            return included
        } catch { throw .preserving(error) }
    }
}
