/// Complete source-owned curve graphs and their same-owner authored request.
public struct OriginalCompleteCurveGraphDomainCover<S: Sendable, E: Sendable, C: Sendable>: Sendable {
    public let family: OriginalCompleteCurveGraphs<S,E,C>
    public let request: OriginalParameterSelection<S,OriginalExactScalarDomain>
    public let depth: ExactScalarDepth

    init(family: OriginalCompleteCurveGraphs<S,E,C>,
        request: OriginalParameterSelection<S,OriginalExactScalarDomain>, depth: ExactScalarDepth) {
        self.family = family; self.request = request; self.depth = depth
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(NativeExactRelationFailure) {
        do {
            try admission.checkpoint()
            try family.admitProof(limits: limits.source, using: &admission)
            try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
            try request.frame.require(limits, &admission)
            try admission.checkpoint()
        } catch { throw .preserving(error) }
    }
}
