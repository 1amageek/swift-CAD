import CADCore

/// Complete material residual retaining both original face sides and all raw ordinals.
public struct OriginalExactNativeMaterialSelfContacts: Sendable {
    public let residual: OriginalExactNativeSelfContacts
    public let first: OriginalExactNativeBoundaryDomain
    public let second: OriginalExactNativeBoundaryDomain
    public let selection: OriginalNativeBoundaryDomain.Selection
    public let firstRefinements: [OriginalExactBoundaryRefinement]
    public let secondRefinements: [OriginalExactBoundaryRefinement]
    init(residual: OriginalExactNativeSelfContacts, first: OriginalExactNativeBoundaryDomain,
        second: OriginalExactNativeBoundaryDomain, selection: OriginalNativeBoundaryDomain.Selection,
        firstRefinements: [OriginalExactBoundaryRefinement], secondRefinements: [OriginalExactBoundaryRefinement]) {
        self.residual = residual; self.first = first; self.second = second; self.selection = selection
        self.firstRefinements = firstRefinements; self.secondRefinements = secondRefinements
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(
        originalCoordinates: [OriginalExactNativeSelfContacts.Field.Value],
        queryField: OriginalExactNativeSelfContacts.Field? = nil,
        domainLimits: OriginalDomainIdentityLimits, rootLimits: ExactRealRootLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try a.checkpoint()
            let field = queryField ?? residual.raw.first.space.frame.scalarField
            try first.source.admitted(limits:domainLimits,queryField:field,using:&a)
            try second.source.admitted(limits:domainLimits,queryField:field,using:&a)
            guard originalCoordinates.count == 4 else { throw NativeExactRelationFailure.invalidDomain }
            for value in originalCoordinates { try a.consumeWork(1); _ = try field.sign(of:value,using:&a) }
            for index in firstRefinements.indices {
                try a.consumeWork(1)
                if let local = try first.source.localCoordinates(at:index,original:originalCoordinates,
                    queryField:field,limits:domainLimits,using:&a),
                    try firstRefinements[index].parameters.contains(localCoordinates:local,queryField:field,
                        rootLimits:rootLimits,using:&a) {
                    try a.checkpoint(); return true
                }
            }
            try a.checkpoint(); return false
        } catch { throw .preserving(error) }
    }
}
