import CADCore

/// Issues exact equality of the authored primitives, without tolerance classification.
public struct OriginalCoincidentConeSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalPhysicalAngleScalarDomain
    public let tolerance: ModelingTolerance
    public init(field:OriginalPhysicalAngleScalarDomain,tolerance:ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public static func angle(_ input:OriginalCoincidentConeInput) -> Double? {
        guard case .analytic(.cone(_,let axis,let angle))=input.first,
            case .analytic(.cone)=input.second,input.first==input.second,
            angle>0,angle<=0.5 else { return nil }
        guard axis == .unitX || axis == .unitY || axis == .unitZ ||
            axis == .init(x:-1,y:0,z:0) || axis == .init(x:0,y:-1,z:0) || axis == .init(x:0,y:0,z:-1) else { return nil }
        return angle
    }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalCoincidentConeInput,
        limits:OriginalSourceIssuanceLimits,using a:inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCoincidentConeSnapshot> {
        let input=copy input
        do {
            return try a.withProofScope { a in
                try a.checkpoint();try a.consumeWork(1)
                guard limits.remainingSourceDepth>=1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard let angle=Self.angle(input) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                guard field.originalRadians==angle else { throw OriginalSourceIssuanceFailure.foreignBinding }
                let s=try field.sine(using:&a),c=try field.cosine(using:&a)
                guard try field.sign(of:s,using:&a) == .positive,try field.sign(of:c,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
                let issuer=DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticCoordinateSurfaceSnapshotProvider(tolerance:tolerance))
                let first=try issuer.bind(input.first,limits:.init(remainingSourceDepth:0),using:&a)
                let second=try issuer.bind(input.second,limits:.init(remainingSourceDepth:0),using:&a)
                let law=DefaultOriginalAnalyticCoordinateIssuer<OriginalAnalyticCoordinateSnapshot,OriginalPhysicalAngleScalarDomain>()
                let fl=try law.issue(source:first,field:field,limits:limits,using:&a)
                let sl=try law.issue(source:second,field:field,limits:limits,using:&a)
                let period=try field.binary64(exactly:2*Double.pi,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCoincidentConeSnapshot.self))
                let result=OriginalCoincidentConeSnapshot(original:input,field:field,firstLaw:fl,secondLaw:sl,
                    sine:s,cosine:c,labelPeriod:period,proofDepth:try a.depth)
                try a.checkpoint();return .init(original:result,sourceDepth:1)
            }
        } catch { throw .init(preserving:error) }
    }
}
