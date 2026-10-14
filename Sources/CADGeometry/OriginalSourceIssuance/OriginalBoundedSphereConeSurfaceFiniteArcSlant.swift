/// Exact ordered root of lambda²-2*b*lambda+C, b=m+r*sin(2*pi*principalU/B).
public struct OriginalBoundedSphereConeSurfaceFiniteArcSlant: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    public let middleOffset: Field.Value
    public let sineCoefficient: Field.Value
    public let constant: Field.Value
    public let coneU: Field.Value
    public let principalConeU: Field.Value
    public let labelPeriod: Field.Value
    /// Zero selects b+sqrt(b²-C); one selects b-sqrt(b²-C).
    public let branch: Int
}
