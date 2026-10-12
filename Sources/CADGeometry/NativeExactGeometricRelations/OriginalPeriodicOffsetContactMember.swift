#if ISSUED_GEOMETRY_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import DI
#endif

/// A selected integer lift retains its complete original source/DI/guard authority.
public struct OriginalPeriodicOffsetContactMember: Sendable {
    public let template: OriginalPeriodicOffsetContactTemplate
    public let originalUV: [OriginalExactScalar]
    public var normalLength: OriginalExactScalar { template.normalLength }
    public var position: [OriginalExactScalar] { template.position }
    public var parameterDimension: Int { template.parameterDimension }
    public var imageDimension: Int { 0 }
    public var fiberDimension: Int { parameterDimension }
    public let isEmpty: Bool
    init(template:OriginalPeriodicOffsetContactTemplate,originalUV:[OriginalExactScalar],isEmpty:Bool) {
        self.template=template;self.originalUV=originalUV;self.isEmpty=isEmpty
    }
    public func contains<A:ExactScalarAdmission & ~Copyable>(_ tuple:[OriginalExactScalar],
        limits:OriginalDomainIdentityLimits,using a:inout A) throws -> Bool {
        try template.admit(limits,&a)
        guard tuple.count==4 else { throw OriginalDomainIdentityFailure.invalidDomain }
        let f=template.field
        for value in tuple { _=try f.sign(of:value,using:&a) }
        guard !isEmpty,try f.compare(tuple[1],originalUV[0],using:&a) == .equal,
            try f.compare(tuple[2],originalUV[1],using:&a) == .equal,
            try f.compare(tuple[3],normalLength,using:&a) == .equal else { try a.checkpoint();return false }
        let domain=try ExactParameterDomain(retaining:template.curveDomain,using:&a)
        let inside=try domain.contains(tuple[0],in:template.curveDomain,using:&a)
        try a.checkpoint();return inside
    }
}
