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

/// Exact conjunction of two selected lifted domains and one retained fundamental L5 relation.
public struct NativeExactSymbolicRelationMember<First: OriginalBSplineSourceReading,
    Second: OriginalBSplineSourceReading>: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let first: OriginalBSplineChartOccurrence<First,Field>
    public let second: OriginalBSplineChartOccurrence<Second,Field>
    public let fundamental: NativeExactParametricRelationPiece<First,Second>
    public let firstInverse: OriginalParameterTransport<First,Field>
    public let secondInverse: OriginalParameterTransport<Second,Field>
    public let depth: ExactScalarDepth

    init(first: OriginalBSplineChartOccurrence<First,Field>,second: OriginalBSplineChartOccurrence<Second,Field>,
        firstInverse: OriginalParameterTransport<First,Field>,secondInverse: OriginalParameterTransport<Second,Field>,
        fundamental: NativeExactParametricRelationPiece<First,Second>,depth: ExactScalarDepth) {
        self.first = first; self.second = second; self.firstInverse = firstInverse
        self.secondInverse = secondInverse; self.fundamental = fundamental; self.depth = depth
    }

    public func contains<A: ExactScalarAdmission & ~Copyable>(firstTuple: borrowing [Field.Value],
        secondTuple: borrowing [Field.Value],domainLimits: OriginalDomainIdentityLimits,
        rootLimits: ExactRealRootLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> Bool {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value:depth.value,coefficient:depth.coefficient)
            guard firstTuple.count == first.selectedImage.arity,secondTuple.count == second.selectedImage.arity else {
                throw NativeExactRelationFailure.invalidDomain
            }
            guard firstInverse.depth <= domainLimits.maximumTransportDepth,
                secondInverse.depth <= domainLimits.maximumTransportDepth else {
                throw OriginalDomainIdentityFailure.transportDepthLimit
            }
            try fundamental.first.law.admitProof(using:&admission)
            try fundamental.second.law.admitProof(using:&admission)
            let relation = fundamental.relation
            try admission.admitDepth(value:relation.components.depth.value,coefficient:relation.components.depth.coefficient)
            let cells = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:relation.original.predicate.source,using:&admission)
            let field = first.selectedImage.frame.scalarField
            // Validate both tuples even when one selected image is empty or excludes its tuple.
            let leftIncluded = try first.selectedImage.contains(firstTuple,queryField:field,limits:domainLimits,using:&admission)
            let rightIncluded = try second.selectedImage.contains(secondTuple,queryField:field,limits:domainLimits,using:&admission)
            guard leftIncluded && rightIncluded else { try admission.checkpoint(); return false }
            let left = try DefaultOriginalParameterTransporter<First,Field>().forward(firstTuple,through:firstInverse,limits:domainLimits,using:&admission)
            let right = try DefaultOriginalParameterTransporter<Second,Field>().forward(secondTuple,through:secondInverse,limits:domainLimits,using:&admission)
            let count = left.count.addingReportingOverflow(right.count)
            guard !count.overflow else { throw ExactScalarFailure.countOverflow }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Field.Value.self))
            var tuple = left; tuple.append(contentsOf:right)
            let point = try cells.point(field:field,coordinates:tuple,using:&admission)
            let domain = ExactParametricRelationDomain<ExactRationalScalarDomain,ExactRealCellDomain<ExactRationalScalarDomain>,ExactRealTopology<ExactRationalScalarDomain>>(
                cells:ExactRealCellDomain<ExactRationalScalarDomain>.self,topology:.init(cells:ExactRealCellDomain<ExactRationalScalarDomain>.self))
            let included = try domain.contains(point,in:relation,rootLimits:rootLimits,using:&admission)
            try admission.checkpoint()
            return included
        } catch { throw .preserving(error) }
    }
}
