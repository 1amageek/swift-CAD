#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension OriginalPlaneBasisReceipt: OriginalPlaneCoordinateQuerying {
    public typealias Field = F
    public func position<A: ExactScalarAdmission & ~Copyable>(u x: F.Value,v y: F.Value,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [F.Value] {
        try OriginalDomainAccess.run(&admission) { a in
            guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            try OriginalDomainAccess.storage(3,F.Value.self,&a)
            var point: [F.Value] = []
            for i in 0..<3 {
                try a.consumeWork(1)
                point.append(try field.adding(origin[i],field.adding(field.multiplying(u[i],x,using:&a),field.multiplying(v[i],y,using:&a),using:&a),using:&a))
            }
            return point
        }
    }
    /// Exact inverse on the original plane; off-plane points are not projections.
    public func parameters<A: ExactScalarAdmission & ~Copyable>(of point: borrowing [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [F.Value] {
        let point = copy point
        return try OriginalDomainAccess.run(&admission) { a in
            guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            guard point.count == 3 else { throw OriginalDomainIdentityFailure.invalidDomain }
            let zero = try field.integer(0,using:&a)
            var constraint = zero,x = zero,y = zero
            for i in 0..<3 {
                try a.consumeWork(1)
                let delta = try field.subtracting(point[i],origin[i],using:&a)
                constraint = try field.adding(constraint,field.multiplying(normal[i],delta,using:&a),using:&a)
                x = try field.adding(x,field.multiplying(u[i],delta,using:&a),using:&a)
                y = try field.adding(y,field.multiplying(v[i],delta,using:&a),using:&a)
            }
            guard try field.sign(of:constraint,using:&a) == .zero else { throw OriginalDomainIdentityFailure.outsideSupport }
            try OriginalDomainAccess.storage(2,F.Value.self,&a); return [x,y]
        }
    }
}
