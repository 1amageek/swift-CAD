#if NATIVE_FAMILY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
#endif

/// L5 tuples use the local coordinates of the two retained original-law owners.
/// Their inverse transports preserve the authored TUV/UVUV coordinates and lifts.
public struct NativeExactParametricRelationPiece<First: OriginalBSplineSourceReading,
    Second: OriginalBSplineSourceReading>: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let first: OriginalDomainBoundRationalChart<First,Field>
    public let second: OriginalDomainBoundRationalChart<Second,Field>
    public let relation: ExactParametricRelation<ExactRationalScalarDomain>
    init(first: OriginalDomainBoundRationalChart<First,Field>,second: OriginalDomainBoundRationalChart<Second,Field>,
        relation: ExactParametricRelation<ExactRationalScalarDomain>) {
        self.first = first; self.second = second; self.relation = relation
    }

    /// Membership uses the retained original-to-local transports, with no solver replay.
    public func contains<A: ExactScalarAdmission & ~Copyable>(
        firstTuple: borrowing [Field.Value],secondTuple: borrowing [Field.Value],
        domainLimits: OriginalDomainIdentityLimits,rootLimits: ExactRealRootLimits,
        using admission: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            guard try first.occurrence.selectedImage.contains(firstTuple,limits:domainLimits,using:&admission),
                try second.occurrence.selectedImage.contains(secondTuple,limits:domainLimits,using:&admission) else { return false }
            let left = try DefaultOriginalParameterTransporter<First,Field>().forward(firstTuple,through:first.inverse,limits:domainLimits,using:&admission)
            let right = try DefaultOriginalParameterTransporter<Second,Field>().forward(secondTuple,through:second.inverse,limits:domainLimits,using:&admission)
            let count = left.count.addingReportingOverflow(right.count)
            guard !count.overflow else { throw ExactScalarFailure.countOverflow }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Field.Value.self))
            var tuple = left; tuple.append(contentsOf:right)
            let cells = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:relation.original.predicate.source,using:&admission)
            let point = try cells.point(field:first.law.field,coordinates:tuple,using:&admission)
            let query = ExactParametricRelationDomain<ExactRationalScalarDomain,ExactRealCellDomain<ExactRationalScalarDomain>,ExactRealTopology<ExactRationalScalarDomain>>(
                cells:ExactRealCellDomain<ExactRationalScalarDomain>.self,topology:.init(cells:ExactRealCellDomain<ExactRationalScalarDomain>.self))
            return try query.contains(point,in:relation,rootLimits:rootLimits,using:&admission)
        } catch { throw .preserving(error) }
    }
}
