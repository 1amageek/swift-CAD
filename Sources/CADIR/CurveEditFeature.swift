import CADCore

public struct CurveEditFeature: Codable, Hashable, Sendable {
    public var source: CurveOutputReference
    public var edits: [CurveEdit]

    public init(
        source: CurveOutputReference,
        edits: [CurveEdit]
    ) {
        self.source = source
        self.edits = edits
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try source.validate()
        guard edits.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Curve edit features must contain at least one edit.")
        }
        for edit in edits {
            try edit.validate(on: source, tolerance: tolerance)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case edits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .edits], in: decoder)
        source = try container.decode(CurveOutputReference.self, forKey: .source)
        edits = try container.decode([CurveEdit].self, forKey: .edits)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(edits, forKey: .edits)
    }
}

public enum CurveEdit: Codable, Hashable, Sendable {
    case setControlPoint(CurveControlPointEdit)
    case setKnot(CurveKnotEdit)
    case setWeight(CurveWeightEdit)

    private enum CodingKeys: String, CodingKey {
        case kind
        case controlPoint
        case knot
        case weight
    }

    private enum Kind: String, Codable {
        case setControlPoint
        case setKnot
        case setWeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .setControlPoint:
            try container.validateOnlyExpectedKeys([.kind, .controlPoint], in: decoder)
            self = .setControlPoint(try container.decode(CurveControlPointEdit.self, forKey: .controlPoint))
        case .setKnot:
            try container.validateOnlyExpectedKeys([.kind, .knot], in: decoder)
            self = .setKnot(try container.decode(CurveKnotEdit.self, forKey: .knot))
        case .setWeight:
            try container.validateOnlyExpectedKeys([.kind, .weight], in: decoder)
            self = .setWeight(try container.decode(CurveWeightEdit.self, forKey: .weight))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .setControlPoint(edit):
            try container.encode(Kind.setControlPoint, forKey: .kind)
            try container.encode(edit, forKey: .controlPoint)
        case let .setKnot(edit):
            try container.encode(Kind.setKnot, forKey: .kind)
            try container.encode(edit, forKey: .knot)
        case let .setWeight(edit):
            try container.encode(Kind.setWeight, forKey: .kind)
            try container.encode(edit, forKey: .weight)
        }
    }

    public func validate(on source: CurveOutputReference, tolerance: ModelingTolerance) throws {
        switch self {
        case let .setControlPoint(edit):
            try edit.validate(on: source, tolerance: tolerance)
        case let .setKnot(edit):
            try edit.validate(on: source)
        case let .setWeight(edit):
            try edit.validate(on: source)
        }
    }
}

public struct CurveControlPointEdit: Codable, Hashable, Sendable {
    public var target: CurveControlPointReference
    public var point: Point3D

    public init(target: CurveControlPointReference, point: Point3D) {
        self.target = target
        self.point = point
    }

    public func validate(on source: CurveOutputReference, tolerance: ModelingTolerance) throws {
        try target.validate()
        guard target.curve == source else {
            throw FeatureEvaluationError.invalidGraph("Curve control point edit target must match the source curve.")
        }
        try point.validate()
    }
}

public struct CurveKnotEdit: Codable, Hashable, Sendable {
    public var target: CurveKnotReference
    public var value: Double

    public init(target: CurveKnotReference, value: Double) {
        self.target = target
        self.value = value
    }

    public func validate(on source: CurveOutputReference) throws {
        try target.validate()
        guard target.curve == source else {
            throw FeatureEvaluationError.invalidGraph("Curve knot edit target must match the source curve.")
        }
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
    }
}

public struct CurveWeightEdit: Codable, Hashable, Sendable {
    public var target: CurveControlPointReference
    public var value: Double

    public init(target: CurveControlPointReference, value: Double) {
        self.target = target
        self.value = value
    }

    public func validate(on source: CurveOutputReference) throws {
        try target.validate()
        guard target.curve == source else {
            throw FeatureEvaluationError.invalidGraph("Curve weight edit target must match the source curve.")
        }
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
        guard value > 0.0 else {
            throw GeometryError.invalidDistance(value)
        }
    }
}
