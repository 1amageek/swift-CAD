import CADCore

public struct InvoluteGearFeature: Codable, Hashable, Sendable {
    public enum Dimension: String, Codable, CaseIterable, Sendable {
        case baseRadius, pitchRadius, tipRadius, rootRadius, filletRadius
        case pitchToothAngle, width, twistAngle, profileError, sweepError

        public var quantityKind: QuantityKind {
            switch self {
            case .pitchToothAngle, .twistAngle: .angle
            default: .length
            }
        }
    }

    public var toothCount: Int
    public var dimensions: [Dimension: CADExpression]
    public var doubleHelical: Bool
    public var maximumSegments: Int
    public var origin: Point3D

    public init(toothCount: Int, dimensions: [Dimension: CADExpression],
        doubleHelical: Bool, maximumSegments: Int = 4096, origin: Point3D = .origin) {
        self.toothCount = toothCount
        self.dimensions = dimensions
        self.doubleHelical = doubleHelical
        self.maximumSegments = maximumSegments
        self.origin = origin
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try origin.validate()
        guard toothCount >= 3, maximumSegments >= 6, toothCount <= maximumSegments / 6,
              Set(dimensions.keys) == Set(Dimension.allCases) else {
            throw FeatureEvaluationError.invalidGraph("Gear source requires every dimension and a complete boundary budget.")
        }
        for expression in dimensions.values { try expression.validateLiteralQuantities() }
    }

    public func resolvedDimensions(
        using resolve: (CADExpression) throws -> Quantity
    ) throws -> [Dimension: Double] {
        var result: [Dimension: Double] = [:]
        for dimension in Dimension.allCases {
            guard let expression = dimensions[dimension] else {
                throw FeatureEvaluationError.invalidGraph("Gear dimension \(dimension.rawValue) is missing.")
            }
            let quantity = try resolve(expression)
            guard quantity.kind == dimension.quantityKind else {
                throw UnitError.expectedQuantity(operation: "involuteGear.\(dimension.rawValue)",
                    expected: dimension.quantityKind, actual: quantity.kind)
            }
            guard quantity.value.isFinite, dimension == .twistAngle || quantity.value > 0 else {
                throw FeatureEvaluationError.invalidGraph("Gear dimension \(dimension.rawValue) is invalid.")
            }
            result[dimension] = quantity.value
        }
        return result
    }

    private enum CodingKeys: String, CodingKey { case toothCount, dimensions, doubleHelical, maximumSegments, origin }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys([.toothCount, .dimensions, .doubleHelical, .maximumSegments, .origin], in: decoder)
        var dimensions: [Dimension: CADExpression] = [:]
        for (key, expression) in try values.decode([String: CADExpression].self, forKey: .dimensions) {
            guard let dimension = Dimension(rawValue: key) else {
                throw FeatureEvaluationError.invalidGraph("Unknown gear dimension \(key).")
            }
            dimensions[dimension] = expression
        }
        self.init(toothCount: try values.decode(Int.self, forKey: .toothCount),
            dimensions: dimensions,
            doubleHelical: try values.decode(Bool.self, forKey: .doubleHelical),
            maximumSegments: try values.decode(Int.self, forKey: .maximumSegments),
            origin: try values.decode(Point3D.self, forKey: .origin))
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(toothCount, forKey: .toothCount)
        try values.encode(Dictionary(uniqueKeysWithValues: dimensions.map { ($0.key.rawValue, $0.value) }),
            forKey: .dimensions)
        try values.encode(doubleHelical, forKey: .doubleHelical)
        try values.encode(maximumSegments, forKey: .maximumSegments)
        try values.encode(origin, forKey: .origin)
    }
}
