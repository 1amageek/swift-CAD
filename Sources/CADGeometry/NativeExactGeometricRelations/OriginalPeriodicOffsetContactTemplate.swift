#if ISSUED_GEOMETRY_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import DI
import SourceIssuer
#endif

/// Complete original contact family over selected T and exact independent integer cycles.
public struct OriginalPeriodicOffsetContactTemplate: Sendable {
    public typealias Base = OriginalExactScalarDomain
    public let field: Base
    public let curveTemplate: Int
    public let surfaceTemplate: Int
    public let curveDomain: ExactParameterSet<Base>
    public let fundamentalUV: [OriginalExactScalar]
    public let normalLength: OriginalExactScalar
    public let position: [OriginalExactScalar]
    /// Integer-ended sets select integer indices; nonperiodic axes select zero.
    public let cycleDomains: [ExactParameterSet<ExactRationalScalarDomain>]
    /// The retained DI/source period theorem transports UV by these exact gains.
    public let periods: [OriginalExactScalar]
    public let parameterDimension: Int
    public var imageDimension: Int { 0 }
    public var fiberDimension: Int { parameterDimension }
    public var isEmpty: Bool { curveDomain.isEmpty || cycleDomains.contains { $0.isEmpty } }
    private let sourceDepth: Int
    private let chartCount: Int
    private let integerRank: Int
    private let proofDepth: ExactScalarDepth
    private let owner: any Sendable
    init(field:Base,curveTemplate:Int,surfaceTemplate:Int,curveDomain:ExactParameterSet<Base>,
        fundamentalUV:[OriginalExactScalar],normalLength:OriginalExactScalar,position:[OriginalExactScalar],
        cycleDomains:[ExactParameterSet<ExactRationalScalarDomain>],periods:[OriginalExactScalar],
        parameterDimension:Int,sourceDepth:Int,chartCount:Int,integerRank:Int,proofDepth:ExactScalarDepth,owner:any Sendable) {
        self.field=field;self.curveTemplate=curveTemplate;self.surfaceTemplate=surfaceTemplate;self.curveDomain=curveDomain
        self.fundamentalUV=fundamentalUV;self.normalLength=normalLength;self.position=position
        self.cycleDomains=cycleDomains;self.periods=periods;self.parameterDimension=parameterDimension
        self.sourceDepth=sourceDepth;self.chartCount=chartCount;self.integerRank=integerRank;self.proofDepth=proofDepth;self.owner=owner
    }
    func admit<A:ExactScalarAdmission & ~Copyable>(_ limits:OriginalDomainIdentityLimits,_ a:inout A) throws {
        try a.checkpoint()
        guard sourceDepth<=limits.source.remainingSourceDepth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
        guard chartCount<=limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        guard integerRank<=limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
        guard limits.maximumTransportDepth>=1 else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
    }
    public func member<A:ExactScalarAdmission & ~Copyable>(cycles:[OriginalParameterCycle],
        limits:OriginalDomainIdentityLimits,using a:inout A) throws -> OriginalPeriodicOffsetContactMember {
        try admit(limits,&a)
        guard cycles.count==2 else { throw OriginalDomainIdentityFailure.invalidDomain }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalExactScalar.self))
        var uv:[OriginalExactScalar]=[];uv.reserveCapacity(2)
        var selected = !curveDomain.isEmpty
        for axis in 0..<2 {
            let domain=try ExactParameterDomain(retaining:cycleDomains[axis],using:&a)
            if try !domain.contains(cycles[axis].original,in:cycleDomains[axis],using:&a) { selected=false }
            let index=try field.rational(exactly:cycles[axis].original,using:&a)
            uv.append(try field.adding(fundamentalUV[axis],field.multiplying(periods[axis],index,using:&a),using:&a))
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPeriodicOffsetContactMember.self))
        let result=OriginalPeriodicOffsetContactMember(template:self,originalUV:uv,isEmpty:!selected)
        try a.checkpoint();return result
    }
}
