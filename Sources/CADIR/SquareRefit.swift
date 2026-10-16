import CADCore
import CADGeometry

/// Square's Refit of a face: the face's outer loop split into four sides at its four sharpest
/// vertices and spanned by Square's fit (`options`), its sides on the face's own edges — G0, or
/// tangent or curvature continuous with the neighbouring face across each, within the allowances
/// beside curved neighbours.
public struct SquareRefit: Hashable, Sendable {
    public var options: SquareFitOptions
    /// The continuity with the neighbouring faces: nil for G0.
    public var order: SurfaceEdgeContinuity.Order?
    /// Free: the sides followed loosely (Weight-scaled), as Square's Free side; a sheet's face
    /// strays from its edges where its net does not hold them.
    public var isFree: Bool
    public var angularAllowance: Double?
    public var curvatureAllowance: Double?

    public init(options: SquareFitOptions = SquareFitOptions(), order: SurfaceEdgeContinuity.Order? = nil,
                angularAllowance: Double? = nil, curvatureAllowance: Double? = nil, isFree: Bool = false) {
        self.options = options
        self.order = order
        self.isFree = isFree
        self.angularAllowance = angularAllowance
        self.curvatureAllowance = curvatureAllowance
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try options.validate(using: &execution)
        guard isFree == false || order == nil else {
            throw FeatureEvaluationError.invalidGraph("A Free refit takes no continuity.")
        }
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case options, order, angularAllowance, curvatureAllowance, isFree = "free"
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.options, .order, .angularAllowance, .curvatureAllowance, .isFree], in: decoder)
        options = try container.decode(SquareFitOptions.self, forKey: .options)
        order = try container.decodeIfPresent(SurfaceEdgeContinuity.Order.self, forKey: .order)
        angularAllowance = try container.decodeIfPresent(Double.self, forKey: .angularAllowance)
        curvatureAllowance = try container.decodeIfPresent(Double.self, forKey: .curvatureAllowance)
        isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encodeIfPresent(angularAllowance, forKey: .angularAllowance)
        try container.encodeIfPresent(curvatureAllowance, forKey: .curvatureAllowance)
        if isFree { try container.encode(true, forKey: .isFree) }
    }
#endif
}

#if !hasFeature(Embedded)
extension SquareRefit: Codable {}
#endif
