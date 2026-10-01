import CADCore

/// How a surface (a Loft's end section, a Square's side) meets a body along one of the body's
/// edges: tangent (G1) or curvature (G2) continuous with the face beside the edge, its
/// cross-boundary derivative scaled by `tension`.
public struct SurfaceEdgeContinuity: Codable, Hashable, Sendable {
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
    /// The largest angle between the surface's and the face's normals along the edge when the face
    /// is curved and the surface approximates its tangent planes; a planar face is met exactly.
    public var angularAllowance: Double?
    /// The largest difference between the surface's and a curved face's principal curvatures
    /// (per length) along the edge, for curvature continuity with a curved face.
    public var curvatureAllowance: Double?

    public init(source: FeatureID, bodyRole: FeaturePort, edge: StableSubshapeReference, order: Order, tension: Double = 1,
                angularAllowance: Double? = nil, curvatureAllowance: Double? = nil) {
        self.source = source
        self.bodyRole = bodyRole
        self.edge = edge
        self.order = order
        self.tension = tension
        self.angularAllowance = angularAllowance
        self.curvatureAllowance = curvatureAllowance
    }

    private enum CodingKeys: String, CodingKey {
        case source, bodyRole, edge, order, tension, angularAllowance, curvatureAllowance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .bodyRole, .edge, .order, .tension, .angularAllowance, .curvatureAllowance], in: decoder)
        source = try container.decode(FeatureID.self, forKey: .source)
        bodyRole = try container.decode(FeaturePort.self, forKey: .bodyRole)
        edge = try container.decode(StableSubshapeReference.self, forKey: .edge)
        order = try container.decode(Order.self, forKey: .order)
        tension = try container.decode(Double.self, forKey: .tension)
        angularAllowance = try container.decodeIfPresent(Double.self, forKey: .angularAllowance)
        curvatureAllowance = try container.decodeIfPresent(Double.self, forKey: .curvatureAllowance)
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
        try container.encodeIfPresent(angularAllowance, forKey: .angularAllowance)
        try container.encodeIfPresent(curvatureAllowance, forKey: .curvatureAllowance)
    }

    public func validate() throws {
        try edge.validate()
        guard bodyRole == .body || bodyRole == .sheet else {
            throw FeatureEvaluationError.invalidGraph("A continuity edge's owner publishes a body or a sheet.")
        }
        guard tension.isFinite, tension > 0 else {
            throw FeatureEvaluationError.invalidGraph("A continuity's tension must be finite and greater than zero.")
        }
        if let angularAllowance {
            guard angularAllowance.isFinite, angularAllowance > 0, angularAllowance < Double.pi / 2 else {
                throw FeatureEvaluationError.invalidGraph("A continuity's angular allowance is a positive angle below a right angle.")
            }
        }
        if let curvatureAllowance {
            guard curvatureAllowance.isFinite, curvatureAllowance > 0 else {
                throw FeatureEvaluationError.invalidGraph("A continuity's curvature allowance is a positive curvature.")
            }
        }
    }
}
