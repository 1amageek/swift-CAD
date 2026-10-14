import CADCore

/// Complete original parent pair, two closed circle charts and primitive UV laws.
public struct OriginalFullSphereConeSurfaceSnapshot: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let original: OriginalFullSphereConeSurfaceInput
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let sphereIsFirst: Bool
    public let field: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let labelPeriod: Field.Value
    public let proofDepth: ExactScalarDepth
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
    public func sectionValues<A: ExactScalarAdmission & ~Copyable>(chart: Int, halfAngle: Field.Value,
        using a: inout A) throws -> OriginalSphereConeSurfaceSectionValues {
        guard chart == 0 || chart == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        return try OriginalSphereConeSurfaceSectionValues.issue(halfAngle: halfAngle, chart: chart,
            sourceSine:sine,sourceCosine:cosine,apex:apex,center:sphereCenter,radius:sphereRadius,using:&a)
    }
}
