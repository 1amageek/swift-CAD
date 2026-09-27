import CADCore

/// A scale about `origin` by one factor along each axis of the frame `xAxis`, `yAxis` and
/// `xAxis × yAxis`; equal factors scale uniformly.
public struct DirectScale: Codable, Hashable, Sendable {
    public let origin: Point3D
    public let xAxis: Vector3D
    public let yAxis: Vector3D
    /// Three unitless factors, along x, y and z.
    public let factors: [CADExpression]

    public init(origin: Point3D, xAxis: Vector3D, yAxis: Vector3D, factors: [CADExpression]) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.factors = factors
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        try xAxis.validate()
        try yAxis.validate()
        guard xAxis.length > tolerance.distance, yAxis.length > tolerance.distance,
              abs(xAxis.dot(yAxis)) <= tolerance.angle * xAxis.length * yAxis.length else {
            throw FeatureEvaluationError.invalidGraph("A scale frame needs two perpendicular axes.")
        }
        guard factors.count == 3 else {
            throw FeatureEvaluationError.invalidGraph("A scale has one factor per frame axis.")
        }
        for factor in factors { try factor.validateLiteralQuantities() }
    }

    private enum CodingKeys: String, CodingKey {
        case origin
        case xAxis
        case yAxis
        case factors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.origin, .xAxis, .yAxis, .factors], in: decoder)
        origin = try container.decode(Point3D.self, forKey: .origin)
        xAxis = try container.decode(Vector3D.self, forKey: .xAxis)
        yAxis = try container.decode(Vector3D.self, forKey: .yAxis)
        factors = try container.decode([CADExpression].self, forKey: .factors)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(xAxis, forKey: .xAxis)
        try container.encode(yAxis, forKey: .yAxis)
        try container.encode(factors, forKey: .factors)
    }
}
