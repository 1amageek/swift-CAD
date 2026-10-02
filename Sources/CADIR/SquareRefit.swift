import CADCore

/// Square's Refit of a face: the face's outer loop split into four sides at its four sharpest
/// vertices and spanned by Square's fit (`options`), its sides on the face's own edges — G0, or
/// tangent or curvature continuous with the neighbouring face across each, within the allowances
/// beside curved neighbours.
public struct SquareRefit: Codable, Hashable, Sendable {
    public var options: SquareFitOptions
    /// The continuity with the neighbouring faces: nil for G0.
    public var order: SurfaceEdgeContinuity.Order?
    public var angularAllowance: Double?
    public var curvatureAllowance: Double?

    public init(options: SquareFitOptions = SquareFitOptions(), order: SurfaceEdgeContinuity.Order? = nil,
                angularAllowance: Double? = nil, curvatureAllowance: Double? = nil) {
        self.options = options
        self.order = order
        self.angularAllowance = angularAllowance
        self.curvatureAllowance = curvatureAllowance
    }

    public func validate() throws {
        try options.validate()
        if let angularAllowance {
            guard angularAllowance.isFinite, angularAllowance > 0, angularAllowance < Double.pi / 2 else {
                throw FeatureEvaluationError.invalidGraph("A refit's angular allowance is a positive angle below a right angle.")
            }
        }
        if let curvatureAllowance {
            guard curvatureAllowance.isFinite, curvatureAllowance > 0 else {
                throw FeatureEvaluationError.invalidGraph("A refit's curvature allowance is positive.")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case options, order, angularAllowance, curvatureAllowance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.options, .order, .angularAllowance, .curvatureAllowance], in: decoder)
        options = try container.decode(SquareFitOptions.self, forKey: .options)
        order = try container.decodeIfPresent(SurfaceEdgeContinuity.Order.self, forKey: .order)
        angularAllowance = try container.decodeIfPresent(Double.self, forKey: .angularAllowance)
        curvatureAllowance = try container.decodeIfPresent(Double.self, forKey: .curvatureAllowance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encodeIfPresent(angularAllowance, forKey: .angularAllowance)
        try container.encodeIfPresent(curvatureAllowance, forKey: .curvatureAllowance)
    }
}
