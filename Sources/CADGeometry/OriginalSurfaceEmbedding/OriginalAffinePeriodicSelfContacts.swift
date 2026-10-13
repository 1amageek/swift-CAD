#if ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION
@testable import CADGeometry
#endif

/// Exact symbolic set difference with every original template/cycle owner retained.
public struct OriginalAffinePeriodicSelfContacts<S: OriginalParameterImageSourceReading>: Sendable where S.Child == BSplineSurface3D {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public typealias Parent = OriginalAffineChildDomainCover<S,OriginalBSplineDomainCover<BSplineSurface3D,Field>>
    public let raw: NativeExactSymbolicSurfacePredicateFamily
    public let parent: Parent
    /// The first view is the authored diagonal; remaining views retain supplied proofs.
    public let identities: [OriginalParameterIdentityRelation<S,Field>]
    public let childCoordinates: OriginalParameterTransport<S,Field>
    /// No raw cell arrays or cycle windows are materialized by the refinement.
    public var templateOrdinals: Range<Int> { raw.templates.indices }
    init(raw: NativeExactSymbolicSurfacePredicateFamily,parent: Parent,
        identities: [OriginalParameterIdentityRelation<S,Field>],childCoordinates: OriginalParameterTransport<S,Field>) {
        self.raw=raw;self.parent=parent;self.identities=identities;self.childCoordinates=childCoordinates
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(template: Int,
        firstCycles: borrowing [OriginalParameterCycle],secondCycles: borrowing [OriginalParameterCycle],
        firstTuple: borrowing [Field.Value],secondTuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits,using a: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try a.checkpoint()
            let transport=DefaultOriginalParameterTransporter<S,Field>()
            _=try parent.source.chart(0,limits:limits.source,using:&a)
            try a.admitDepth(value:raw.depth.value,coefficient:raw.depth.coefficient)
            guard identities.count<=limits.maximumIdentityProofs else { throw OriginalDomainIdentityFailure.identityLimit }
            try transport.admitted(childCoordinates,limits:limits,using:&a)
            let issuer=DefaultOriginalParameterIdentityIssuer<S,Field>()
            for identity in identities { _=try issuer.relation(of:identity.receipt,limits:limits,using:&a) }
            let leftIncluded=try parent.effective.contains(firstTuple,limits:limits,using:&a)
            let rightIncluded=try parent.effective.contains(secondTuple,limits:limits,using:&a)
            let member=try raw.member(template:template,firstCycles:firstCycles,secondCycles:secondCycles,limits:limits,using:&a)
            if !leftIncluded || !rightIncluded { try a.checkpoint();return false }
            // The checked inverse preserves every selected original parent coordinate.
            let left=try transport.forward(firstTuple,through:childCoordinates,limits:limits,using:&a)
            let right=try transport.forward(secondTuple,through:childCoordinates,limits:limits,using:&a)
            var included=try member.contains(firstTuple:left,secondTuple:right,domainLimits:limits,using:&a)
            for identity in identities {
                try a.consumeWork(1)
                let decision=try issuer.decide(identity.receipt,left:firstTuple,right:secondTuple,limits:limits,using:&a)
                if decision == .proven { included=false }
            }
            try a.checkpoint();return included
        } catch { throw NativeExactRelationFailure.preserving(error) }
    }
}
