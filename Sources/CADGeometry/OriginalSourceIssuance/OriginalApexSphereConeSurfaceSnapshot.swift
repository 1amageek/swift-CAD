import CADCore

/// Original sphere/cone metric factors as lambda*(lambda-2*sin(alpha)*sin(theta)).
public struct OriginalApexSphereConeSurfaceSnapshot: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let original: OriginalApexSphereConeSurfaceInput
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let sphereIsFirst: Bool
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let labelPeriod: Field.Value
    public let proofDepth: ExactScalarDepth
    public func nodeTraversal<A:ExactScalarAdmission & ~Copyable>(branch:Int,using a:inout A) throws -> OriginalSphereConeNodeTraversal {
        try a.checkpoint();try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        guard branch==0 || branch==1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSphereConeNodeTraversal.self))
        let result=OriginalSphereConeNodeTraversal(source:self,branch:branch,proofDepth:proofDepth)
        try a.checkpoint();return result
    }
    public func sectionValues<A: ExactScalarAdmission & ~Copyable>(chart: Int, halfAngle: Field.Value,
        using a: inout A) throws -> OriginalApexSphereConeSurfaceValues {
        guard chart == 0 || chart == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        return try OriginalApexSphereConeSurfaceValues.issue(source: self, chart: chart, halfAngle: halfAngle, using: &a)
    }
}
