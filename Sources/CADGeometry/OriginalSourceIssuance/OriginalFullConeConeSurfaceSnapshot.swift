import CADCore

/// Whole original pair and two independent physical coefficient owners.
public struct OriginalFullConeConeSurfaceSnapshot: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let original: OriginalFullConeConeSurfaceInput
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let referenceIsFirst: Bool
    public let field: Field
    public let referenceField: OriginalPhysicalAngleScalarDomain
    public let parameterizedField: OriginalPhysicalAngleScalarDomain
    public let referenceSine: OriginalPhysicalAngleValue
    public let referenceCosine: OriginalPhysicalAngleValue
    public let parameterizedSine: Field.Value
    public let parameterizedCosine: Field.Value
    public let labelPeriod: Field.Value
    public let proofDepth: ExactScalarDepth
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws {
        try a.checkpoint(); try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        _ = try referenceField.importing(referenceSine, using: &a)
        _ = try referenceField.importing(referenceCosine, using: &a)
        _ = try field.importing(parameterizedSine, using: &a)
        _ = try field.importing(parameterizedCosine, using: &a)
        try a.checkpoint()
    }
    public func sectionValues<A: ExactScalarAdmission & ~Copyable>(chart: Int, halfAngle: Field.Value,
        using a: inout A) throws -> OriginalConeConeSurfaceSectionValues {
        try admitProof(using: &a)
        return try OriginalConeConeSurfaceSectionValues.issue(source: self, chart: chart, halfAngle: halfAngle, using: &a)
    }
}
