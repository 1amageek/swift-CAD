import CADCore

/// Complete original pair, critical half-angle interval and primitive UV laws.
public struct OriginalBoundedSphereConeSurfaceSnapshot: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let original: OriginalBoundedSphereConeSurfaceInput
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let sphereIsFirst: Bool
    public let physical: OriginalPhysicalAngleScalarDomain
    public let field: Field
    public let criticalField: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let lowerHalfAngle: Field.Value
    public let upperHalfAngle: Field.Value
    public let labelPeriod: Field.Value
    public let proofDepth: ExactScalarDepth
    let endpointSine:Field.Value
    let endpointCosine:Field.Value
    let endpointSlant:Field.Value
    public var apex:Point3D {
        let value=sphereIsFirst ? original.second:original.first
        guard case .analytic(.cone(let apex,_,_))=value else { preconditionFailure("Source-issued cone invariant.") }
        return apex
    }
    public var sphereCenter:Point3D {
        let value=sphereIsFirst ? original.first:original.second
        guard case .analytic(.sphere(let center,_))=value else { preconditionFailure("Source-issued sphere invariant.") }
        return center
    }
    public var sphereRadius:Double {
        let value=sphereIsFirst ? original.first:original.second
        guard case .analytic(.sphere(_,let radius))=value else { preconditionFailure("Source-issued sphere invariant.") }
        return radius
    }
    public func sectionValues<A: ExactScalarAdmission & ~Copyable>(halfAngle: Field.Value,
        using a: inout A) throws -> OriginalSphereConeSurfaceSectionValues {
        let lower=try criticalField.compare(halfAngle,lowerHalfAngle,using:&a) == .equal
        let upper=try criticalField.compare(halfAngle,upperHalfAngle,using:&a) == .equal
        if lower || upper {
            return try OriginalSphereConeSurfaceSectionValues.endpoint(halfAngle:halfAngle,
                sine:endpointSine,cosine:lower ? endpointCosine:criticalField.negated(endpointCosine,using:&a),
                slant:endpointSlant,sourceSine:sine,sourceCosine:cosine,apex:apex,using:&a)
        }
        return try OriginalSphereConeSurfaceSectionValues.issue(halfAngle:halfAngle,chart:0,
            sourceSine:sine,sourceCosine:cosine,apex:apex,center:sphereCenter,radius:sphereRadius,discriminantRoot:true,using:&a)
    }
}
