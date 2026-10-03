public struct BSplineKnotRemovalResult<Geometry: Sendable>: Sendable {
    public let geometry: Geometry
    public let removedMultiplicity: Int
    /// An outward-rounded upper bound over the entire original parameter domain.
    public let certifiedMaximumDeviation: Double

    public init(geometry: Geometry, removedMultiplicity: Int, certifiedMaximumDeviation: Double) {
        self.geometry = geometry
        self.removedMultiplicity = removedMultiplicity
        self.certifiedMaximumDeviation = certifiedMaximumDeviation
    }
}
