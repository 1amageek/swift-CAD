import CADCore

public struct ExtrudeFeature: Codable, Sendable, Hashable {
    public var section: SectionReference
    public var distance: CADExpression
    public var startDistance: CADExpression?
    public var direction: ExtrudeDirection
    public var operation: SolidOperation
    public var resultKind: ExtrudeResultKind

    public init(
        profile: ProfileReference,
        distance: CADExpression,
        startDistance: CADExpression? = nil,
        direction: ExtrudeDirection = .normal,
        operation: SolidOperation = .newBody,
        resultKind: ExtrudeResultKind = .solid
    ) {
        self.init(section: .profile(profile), distance: distance, startDistance: startDistance, direction: direction,
                  operation: operation, resultKind: resultKind)
    }

    public init(
        section: SectionReference,
        distance: CADExpression,
        startDistance: CADExpression? = nil,
        direction: ExtrudeDirection = .normal,
        operation: SolidOperation = .newBody,
        resultKind: ExtrudeResultKind
    ) {
        self.section = section
        self.distance = distance
        self.startDistance = startDistance
        self.direction = direction
        self.operation = operation
        self.resultKind = resultKind
    }

    private enum CodingKeys: String, CodingKey {
        case section
        case distance
        case startDistance
        case direction
        case operation
        case resultKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.section, .distance, .startDistance, .direction, .operation, .resultKind],
            in: decoder
        )
        section = try container.decode(SectionReference.self, forKey: .section)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        startDistance = try container.decodeIfPresent(CADExpression.self, forKey: .startDistance)
        direction = try container.decode(ExtrudeDirection.self, forKey: .direction)
        operation = try container.decode(SolidOperation.self, forKey: .operation)
        resultKind = try container.decode(ExtrudeResultKind.self, forKey: .resultKind)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section, forKey: .section)
        try container.encode(distance, forKey: .distance)
        try container.encodeIfPresent(startDistance, forKey: .startDistance)
        try container.encode(direction, forKey: .direction)
        try container.encode(operation, forKey: .operation)
        try container.encode(resultKind, forKey: .resultKind)
    }

    public func validate() throws {
        try section.validate()
        try distance.validateLiteralQuantities()
        try startDistance?.validateLiteralQuantities()
        guard direction != .symmetric || startDistance == nil else {
            throw FeatureEvaluationError.invalidGraph("Symmetric extrusion cannot also specify a start position.")
        }
        guard resultKind == .sheet || section.isProfile else {
            throw FeatureEvaluationError.invalidGraph("A curve extrusion requires sheet output.")
        }
        if case .vector(let vector) = direction { try vector.validate() }
    }

    /// Resolves signed axial endpoints once for geometry, measurement and editing.
    public func resolvedAxialRange(
        tolerance: ModelingTolerance,
        resolve: (CADExpression) throws -> Quantity
    ) throws -> ClosedRange<Double> {
        try validate()
        try tolerance.validate()
        func length(_ expression: CADExpression) throws -> Double {
            let quantity = try resolve(expression)
            guard quantity.kind == .length else {
                throw UnitError.expectedQuantity(operation: "extrude.extent", expected: .length, actual: quantity.kind)
            }
            guard quantity.value.isFinite else {
                throw FeatureEvaluationError.invalidDistance(quantity.value)
            }
            return quantity.value
        }
        let end = try length(distance)
        if direction == .symmetric {
            guard end > tolerance.distance else { throw FeatureEvaluationError.invalidDistance(end) }
            return (-end / 2)...(end / 2)
        }
        let start = try startDistance.map(length) ?? 0
        let span = abs(end - start)
        guard span.isFinite, span > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(span)
        }
        return min(start, end)...max(start, end)
    }
}

/// Which body a linear extrusion builds.
///
/// A solid extrusion caps both ends of the swept wall; a sheet extrusion leaves them open and
/// sews the wall alone. The profile is the same value in both cases, so the choice belongs to the
/// feature rather than to the profile it consumes. Open curves produce sheets only.
public enum ExtrudeResultKind: String, Codable, Sendable, Hashable {
    case solid
    case sheet
}

public enum SolidOperation: String, Codable, Sendable, Hashable {
    case newBody
}

public enum ExtrudeDirection: Codable, Sendable, Hashable {
    case normal
    case vector(Vector3D)
    case symmetric

    private enum CodingKeys: String, CodingKey {
        case kind
        case vector
    }

    private enum Kind: String, Codable {
        case normal
        case vector
        case symmetric
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .normal:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .normal
        case .vector:
            try container.validateOnlyExpectedKeys([.kind, .vector], in: decoder)
            self = .vector(try container.decode(Vector3D.self, forKey: .vector))
        case .symmetric:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .symmetric
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .normal:
            try container.encode(Kind.normal, forKey: .kind)
        case let .vector(vector):
            try container.encode(Kind.vector, forKey: .kind)
            try container.encode(vector, forKey: .vector)
        case .symmetric:
            try container.encode(Kind.symmetric, forKey: .kind)
        }
    }
}
