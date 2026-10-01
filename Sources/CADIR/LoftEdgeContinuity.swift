import CADCore

/// How a Loft meets the body at an end section that runs along one of the body's edges: tangent
/// (G1) or curvature (G2) continuous with the face beside the edge the loft leaves (or arrives
/// at), its cross-boundary derivative `tension` times the distance between the end sections.
public struct LoftEdgeContinuity: Codable, Hashable, Sendable {
    public enum Order: String, Codable, Hashable, Sendable {
        case tangent
        case curvature
    }

    /// The feature whose body or sheet owns the edge.
    public var source: FeatureID
    /// The port the owning feature publishes the edge's body on: `.body` or `.sheet`.
    public var bodyRole: FeaturePort
    public var edge: StableSubshapeReference
    public var order: Order
    public var tension: Double

    public init(source: FeatureID, bodyRole: FeaturePort, edge: StableSubshapeReference, order: Order, tension: Double = 1) {
        self.source = source
        self.bodyRole = bodyRole
        self.edge = edge
        self.order = order
        self.tension = tension
    }

    private enum CodingKeys: String, CodingKey {
        case source, bodyRole, edge, order, tension
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .bodyRole, .edge, .order, .tension], in: decoder)
        source = try container.decode(FeatureID.self, forKey: .source)
        bodyRole = try container.decode(FeaturePort.self, forKey: .bodyRole)
        edge = try container.decode(StableSubshapeReference.self, forKey: .edge)
        order = try container.decode(Order.self, forKey: .order)
        tension = try container.decode(Double.self, forKey: .tension)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(bodyRole, forKey: .bodyRole)
        try container.encode(edge, forKey: .edge)
        try container.encode(order, forKey: .order)
        try container.encode(tension, forKey: .tension)
    }

    public func validate() throws {
        try edge.validate()
        guard bodyRole == .body || bodyRole == .sheet else {
            throw FeatureEvaluationError.invalidGraph("A Loft continuity edge's owner publishes a body or a sheet.")
        }
        guard tension.isFinite, tension > 0 else {
            throw FeatureEvaluationError.invalidGraph("A Loft continuity's tension must be finite and greater than zero.")
        }
    }
}
