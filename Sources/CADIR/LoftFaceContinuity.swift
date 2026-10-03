import CADCore

/// Tangent or curvature continuity of a Loft at a face section: across each edge of the face's
/// boundary the Loft leaves (or arrives) as the face beside that edge runs on, the section's own
/// face aside (Plasticity's Start and End Continuity for a face). The allowances are those of
/// `SurfaceEdgeContinuity`, needed where a face beside the boundary is curved.
public struct LoftFaceContinuity: Codable, Hashable, Sendable {
    public var order: SurfaceEdgeContinuity.Order
    public var tension: Double
    public var angularAllowance: Double?
    public var curvatureAllowance: Double?

    public init(order: SurfaceEdgeContinuity.Order, tension: Double = 1, angularAllowance: Double? = nil, curvatureAllowance: Double? = nil) {
        self.order = order
        self.tension = tension
        self.angularAllowance = angularAllowance
        self.curvatureAllowance = curvatureAllowance
    }

    private enum CodingKeys: String, CodingKey {
        case order, tension, angularAllowance, curvatureAllowance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.order, .tension, .angularAllowance, .curvatureAllowance], in: decoder)
        order = try container.decode(SurfaceEdgeContinuity.Order.self, forKey: .order)
        tension = try container.decode(Double.self, forKey: .tension)
        angularAllowance = try container.decodeIfPresent(Double.self, forKey: .angularAllowance)
        curvatureAllowance = try container.decodeIfPresent(Double.self, forKey: .curvatureAllowance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order, forKey: .order)
        try container.encode(tension, forKey: .tension)
        try container.encodeIfPresent(angularAllowance, forKey: .angularAllowance)
        try container.encodeIfPresent(curvatureAllowance, forKey: .curvatureAllowance)
    }

    public func validate() throws {
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
                throw FeatureEvaluationError.invalidGraph("A continuity's curvature allowance must be finite and greater than zero.")
            }
        }
    }

    /// The continuity across one boundary edge of the face section, owned by `source`.
    public func along(edge: StableSubshapeReference, source: FeatureID, bodyRole: FeaturePort) -> SurfaceEdgeContinuity {
        SurfaceEdgeContinuity(source: source, bodyRole: bodyRole, edge: edge, order: order, tension: tension,
                              angularAllowance: angularAllowance, curvatureAllowance: curvatureAllowance)
    }
}
