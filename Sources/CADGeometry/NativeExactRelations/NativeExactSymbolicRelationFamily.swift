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

/// Complete symbolic parameter family; original covers own integer indices and requests.
public struct NativeExactSymbolicRelationFamily<First: OriginalBSplineSourceReading,
    Second: OriginalBSplineSourceReading>: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let first: OriginalBSplineDomainCover<First,Field>
    public let second: OriginalBSplineDomainCover<Second,Field>
    public let templates: [NativeExactSymbolicRelationTemplate<First,Second>]
    public let depth: ExactScalarDepth

    init(first: OriginalBSplineDomainCover<First,Field>,second: OriginalBSplineDomainCover<Second,Field>,
        templates: [NativeExactSymbolicRelationTemplate<First,Second>],depth: ExactScalarDepth) {
        self.first = first; self.second = second; self.templates = templates; self.depth = depth
    }

    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,
        firstCycles: borrowing [OriginalParameterCycle],secondCycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactSymbolicRelationMember<First,Second> {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value:depth.value,coefficient:depth.coefficient)
            guard template >= 0,template < templates.count else { throw NativeExactRelationFailure.invalidDomain }
            let pair = templates[template]
            try pair.fundamental.first.law.admitProof(using:&admission)
            try pair.fundamental.second.law.admitProof(using:&admission)
            let left = try first.member(template:pair.firstTemplate,cycles:firstCycles,limits:limits,using:&admission)
            let right = try second.member(template:pair.secondTemplate,cycles:secondCycles,limits:limits,using:&admission)
            let inverseLeft = try DefaultOriginalParameterTransporter<First,Field>().inverse(left.correspondence,limits:limits,using:&admission)
            let inverseRight = try DefaultOriginalParameterTransporter<Second,Field>().inverse(right.correspondence,limits:limits,using:&admission)
            var valueDepth=depth.value,coefficientDepth=depth.coefficient
            for axis in inverseLeft.local.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            for axis in inverseLeft.image.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            for axis in inverseRight.local.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            for axis in inverseRight.image.axes { try admission.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:NativeExactSymbolicRelationMember<First,Second>.self))
            let result = NativeExactSymbolicRelationMember(first:left,second:right,firstInverse:inverseLeft,
                secondInverse:inverseRight,fundamental:pair.fundamental,depth:try ExactScalarDepth(value:valueDepth,coefficient:coefficientDepth))
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }
}
