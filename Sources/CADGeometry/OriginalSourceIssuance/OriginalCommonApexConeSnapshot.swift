import CADCore

/// Independent physical bounds prove that the original cones share only their apex.
public struct OriginalCommonApexConeSnapshot: Sendable {
    public enum Exclusion: Sendable { case orthogonalDirections, distinctPhysicalAngles }
    public typealias Field = ExactRationalScalarDomain
    public let original: OriginalCommonApexConeInput
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let referenceIsFirst: Bool
    public let field: Field
    public let referenceField: OriginalPhysicalAngleScalarDomain
    public let parameterizedField: OriginalPhysicalAngleScalarDomain
    public let referenceSine: OriginalPhysicalAngleValue
    public let referenceCosine: OriginalPhysicalAngleValue
    public let parameterizedSine: OriginalPhysicalAngleValue
    public let parameterizedCosine: OriginalPhysicalAngleValue
    public let labelPeriod: Field.Value
    public let position: (x:Field.Value,y:Field.Value,z:Field.Value)
    public let exclusion: Exclusion
    public let proofDepth: ExactScalarDepth
}
