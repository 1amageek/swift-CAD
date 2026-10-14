import CADCore

/// Complete original pair, critical half-angle interval and primitive UV laws.
public struct OriginalBoundedSphereConeSurfaceSnapshot: Sendable {
    public typealias Field = OriginalCertifiedSphereConePlaneRoot.Field
    public let original: OriginalBoundedSphereConeSurfaceInput
    public let firstLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let secondLaw: OriginalAnalyticCoordinateLawReceipt<OriginalAnalyticCoordinateSnapshot, Field>
    public let sphereIsFirst: Bool
    public let arc: OriginalCertifiedSphereConeBoundedArc
    public let field: Field
    public let criticalField: Field
    public let sine: Field.Value
    public let cosine: Field.Value
    public let lowerHalfAngle: Field.Value
    public let upperHalfAngle: Field.Value
    public let labelPeriod: Field.Value
    public let proofDepth: ExactScalarDepth
}
