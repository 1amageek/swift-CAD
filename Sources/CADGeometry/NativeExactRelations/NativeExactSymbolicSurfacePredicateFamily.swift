#if ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION
@testable import CADGeometry
#endif

/// A complete symbolic set description, without an emptiness or topology claim.
public struct NativeExactSymbolicSurfacePredicateFamily: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public typealias Cover = OriginalBSplineDomainCover<BSplineSurface3D,Field>
    public struct Template: Sendable {
        public let firstTemplate: Int
        public let secondTemplate: Int
        public let first: OriginalDomainBoundRationalChart<BSplineSurface3D,Field>
        public let second: OriginalDomainBoundRationalChart<BSplineSurface3D,Field>
        public let source: ExactParametricRelationSource<ExactRationalScalarDomain>
    }
    public struct Member: Sendable {
        public let first: OriginalBSplineChartOccurrence<BSplineSurface3D,Field>
        public let second: OriginalBSplineChartOccurrence<BSplineSurface3D,Field>
        public let fundamental: Template
        public let firstInverse: OriginalParameterTransport<BSplineSurface3D,Field>
        public let secondInverse: OriginalParameterTransport<BSplineSurface3D,Field>
        public let depth: ExactScalarDepth

        public func contains<A: ExactScalarAdmission & ~Copyable>(firstTuple: borrowing [Field.Value],
            secondTuple: borrowing [Field.Value],domainLimits: OriginalDomainIdentityLimits,
            using a: inout A) throws(NativeExactRelationFailure) -> Bool {
            do {
                try a.checkpoint();try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
                let f=first.selectedImage.frame.scalarField
                let transport=DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
                try transport.admitted(firstInverse,limits:domainLimits,using:&a)
                try transport.admitted(secondInverse,limits:domainLimits,using:&a)
                try fundamental.first.law.admitProof(using:&a);try fundamental.second.law.admitProof(using:&a)
                let leftIncluded=try first.selectedImage.contains(firstTuple,queryField:f,limits:domainLimits,using:&a)
                let rightIncluded=try second.selectedImage.contains(secondTuple,queryField:f,limits:domainLimits,using:&a)
                guard leftIncluded && rightIncluded else { try a.checkpoint();return false }
                let left=try transport.forward(firstTuple,through:firstInverse,limits:domainLimits,using:&a)
                let right=try transport.forward(secondTuple,through:secondInverse,limits:domainLimits,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
                var tuple=left;tuple.append(contentsOf:right)
                let source=fundamental.source
                let cells=try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:source.predicate.source,using:&a)
                let ring=cells.polynomials
                var included=true
                // Original equations avoid discarding any guarded branch through
                // compiler simplification; all three and both weights are checked.
                for law in source.rawEquations {
                    try a.consumeWork(1)
                    let value=try ring.evaluated(law,at:tuple,using:&a)
                    try a.admitDepth(value:value.depth.value,coefficient:value.depth.coefficient)
                    if try f.sign(of:value.value,using:&a) != .zero { included=false }
                }
                func checkWeight(_ map: ExactParametricMap<ExactRationalScalarDomain>,_ coordinates:[Field.Value]) throws -> Bool {
                    let domain=try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:map.original,using:&a)
                    let value=try domain.polynomials.evaluated(map.original.polynomials[3],at:coordinates,using:&a)
                    try a.admitDepth(value:value.depth.value,coefficient:value.depth.coefficient)
                    return try f.sign(of:value.value,using:&a) != .zero
                }
                let leftWeight=try checkWeight(source.first,left),rightWeight=try checkWeight(source.second,right)
                try a.checkpoint();return included && leftWeight && rightWeight
            } catch { throw .preserving(error) }
        }
    }
    public let first: Cover
    public let second: Cover
    public let templates: [Template]
    public let depth: ExactScalarDepth
    init(first: Cover,second: Cover,templates:[Template],depth:ExactScalarDepth) {
        self.first=first;self.second=second;self.templates=templates;self.depth=depth
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,
        firstCycles: borrowing [OriginalParameterCycle],secondCycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using a: inout A) throws(NativeExactRelationFailure) -> Member {
        do {
            try a.checkpoint();try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            guard template>=0,template<templates.count else { throw NativeExactRelationFailure.invalidDomain }
            let pair=templates[template]
            try pair.first.law.admitProof(using:&a);try pair.second.law.admitProof(using:&a)
            let left=try first.member(template:pair.firstTemplate,cycles:firstCycles,limits:limits,using:&a)
            let right=try second.member(template:pair.secondTemplate,cycles:secondCycles,limits:limits,using:&a)
            let transport=DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
            let li=try transport.inverse(left.correspondence,limits:limits,using:&a)
            let ri=try transport.inverse(right.correspondence,limits:limits,using:&a)
            var valueDepth=depth.value,coefficientDepth=depth.coefficient
            func includeDepth(_ map: OriginalParameterTransport<BSplineSurface3D,Field>) throws {
                for axis in map.local.axes { try a.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
                for axis in map.image.axes { try a.consumeWork(1);valueDepth=max(valueDepth,axis.depth.value);coefficientDepth=max(coefficientDepth,axis.depth.coefficient) }
            }
            try includeDepth(li);try includeDepth(ri)
            let memberDepth=try ExactScalarDepth(value:valueDepth,coefficient:coefficientDepth)
            try a.admitDepth(value:memberDepth.value,coefficient:memberDepth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Member.self))
            let result=Member(first:left,second:right,fundamental:pair,firstInverse:li,secondInverse:ri,depth:memberDepth)
            try a.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
