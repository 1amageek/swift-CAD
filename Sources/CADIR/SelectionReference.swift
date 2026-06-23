import CADCore

public struct CurveOutputReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    public var curveIndex: Int

    public init(featureID: FeatureID, curveIndex: Int = 0) {
        self.featureID = featureID
        self.curveIndex = curveIndex
    }

    public func validate() throws {
        guard curveIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve output reference index must not be negative.")
        }
    }
}

public struct CurveParameterReference: Codable, Hashable, Sendable {
    public var curve: CurveOutputReference
    public var parameter: Double

    public init(curve: CurveOutputReference, parameter: Double) {
        self.curve = curve
        self.parameter = parameter
    }

    public func validate() throws {
        try curve.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidCoordinate(parameter)
        }
    }
}

public struct CurveSpanReference: Codable, Hashable, Sendable {
    public var curve: CurveOutputReference
    public var spanIndex: Int

    public init(curve: CurveOutputReference, spanIndex: Int) {
        self.curve = curve
        self.spanIndex = spanIndex
    }

    public func validate() throws {
        try curve.validate()
        guard spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve span reference index must not be negative.")
        }
    }
}

public struct CurveControlPointReference: Codable, Hashable, Sendable {
    public var curve: CurveOutputReference
    public var controlPointIndex: Int

    public init(curve: CurveOutputReference, controlPointIndex: Int) {
        self.curve = curve
        self.controlPointIndex = controlPointIndex
    }

    public func validate() throws {
        try curve.validate()
        guard controlPointIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve control point reference index must not be negative.")
        }
    }
}

public struct CurveKnotReference: Codable, Hashable, Sendable {
    public var curve: CurveOutputReference
    public var knotIndex: Int

    public init(curve: CurveOutputReference, knotIndex: Int) {
        self.curve = curve
        self.knotIndex = knotIndex
    }

    public func validate() throws {
        try curve.validate()
        guard knotIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve knot reference index must not be negative.")
        }
    }
}

public enum CurveSubobjectReference: Codable, Hashable, Sendable {
    case whole(CurveOutputReference)
    case parameter(CurveParameterReference)
    case span(CurveSpanReference)
    case controlPoint(CurveControlPointReference)
    case knot(CurveKnotReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case whole
        case parameter
        case span
        case controlPoint
        case knot
    }

    private enum Kind: String, Codable {
        case whole
        case parameter
        case span
        case controlPoint
        case knot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .whole:
            try container.validateOnlyExpectedKeys([.kind, .whole], in: decoder)
            self = .whole(try container.decode(CurveOutputReference.self, forKey: .whole))
        case .parameter:
            try container.validateOnlyExpectedKeys([.kind, .parameter], in: decoder)
            self = .parameter(try container.decode(CurveParameterReference.self, forKey: .parameter))
        case .span:
            try container.validateOnlyExpectedKeys([.kind, .span], in: decoder)
            self = .span(try container.decode(CurveSpanReference.self, forKey: .span))
        case .controlPoint:
            try container.validateOnlyExpectedKeys([.kind, .controlPoint], in: decoder)
            self = .controlPoint(try container.decode(CurveControlPointReference.self, forKey: .controlPoint))
        case .knot:
            try container.validateOnlyExpectedKeys([.kind, .knot], in: decoder)
            self = .knot(try container.decode(CurveKnotReference.self, forKey: .knot))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .whole(reference):
            try container.encode(Kind.whole, forKey: .kind)
            try container.encode(reference, forKey: .whole)
        case let .parameter(reference):
            try container.encode(Kind.parameter, forKey: .kind)
            try container.encode(reference, forKey: .parameter)
        case let .span(reference):
            try container.encode(Kind.span, forKey: .kind)
            try container.encode(reference, forKey: .span)
        case let .controlPoint(reference):
            try container.encode(Kind.controlPoint, forKey: .kind)
            try container.encode(reference, forKey: .controlPoint)
        case let .knot(reference):
            try container.encode(Kind.knot, forKey: .kind)
            try container.encode(reference, forKey: .knot)
        }
    }

    public func validate() throws {
        switch self {
        case let .whole(reference):
            try reference.validate()
        case let .parameter(reference):
            try reference.validate()
        case let .span(reference):
            try reference.validate()
        case let .controlPoint(reference):
            try reference.validate()
        case let .knot(reference):
            try reference.validate()
        }
    }
}

public enum SelectionReference: Codable, Hashable, Sendable {
    case topology(PersistentName)
    case curve(CurveSubobjectReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case topology
        case curve
    }

    private enum Kind: String, Codable {
        case topology
        case curve
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .topology:
            try container.validateOnlyExpectedKeys([.kind, .topology], in: decoder)
            self = .topology(try container.decode(PersistentName.self, forKey: .topology))
        case .curve:
            try container.validateOnlyExpectedKeys([.kind, .curve], in: decoder)
            self = .curve(try container.decode(CurveSubobjectReference.self, forKey: .curve))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .topology(name):
            try container.encode(Kind.topology, forKey: .kind)
            try container.encode(name, forKey: .topology)
        case let .curve(reference):
            try container.encode(Kind.curve, forKey: .kind)
            try container.encode(reference, forKey: .curve)
        }
    }

    public func validate() throws {
        switch self {
        case let .topology(name):
            try name.validate()
        case let .curve(reference):
            try reference.validate()
        }
    }
}
