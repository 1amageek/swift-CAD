/// Describes the requested output, independently of the dimension of the exact solution set.
public enum ExactIntersectionResultRepresentation: Sendable {
    /// Legacy numerical point arrays, with optional retained exact relations.
    case numericalRepresentatives
    /// All exact contacts and strata are retained; numerical point arrays were not requested.
    case exactRelation
}
