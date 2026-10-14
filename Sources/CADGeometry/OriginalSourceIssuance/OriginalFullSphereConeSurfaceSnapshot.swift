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
    public func sectionValues<A: ExactScalarAdmission & ~Copyable>(chart: Int, halfAngle: Field.Value,
        using a: inout A) throws -> OriginalSphereConeSurfaceSectionValues {
        guard chart == 0 || chart == 1 else { throw OriginalSourceIssuanceFailure.invalidSource }
        return try OriginalSphereConeSurfaceSectionValues.issue(halfAngle: halfAngle, chart: chart,
            sourceSine: sine, sourceCosine: cosine, apexX: 1, constant: 8, isDoubleRoot: false, using: &a)
    }
}
