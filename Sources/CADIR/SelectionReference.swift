import CADCore

public struct EdgeReference: Codable, Hashable, Sendable {
    public var edgeName: PersistentName

    public init(edgeName: PersistentName) {
        self.edgeName = edgeName
    }

    public func validate() throws {
        try edgeName.validate()
    }
}

public struct EdgeParameterReference: Codable, Hashable, Sendable {
    public var edge: EdgeReference
    public var parameter: Double

    public init(edge: EdgeReference, parameter: Double) {
        self.edge = edge
        self.parameter = parameter
    }

    public func validate() throws {
        try edge.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidCoordinate(parameter)
        }
    }
}

public enum EdgeSubobjectReference: Codable, Hashable, Sendable {
    case whole(EdgeReference)
    case parameter(EdgeParameterReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case whole
        case parameter
    }

    private enum Kind: String, Codable {
        case whole
        case parameter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .whole:
            try container.validateOnlyExpectedKeys([.kind, .whole], in: decoder)
            self = .whole(try container.decode(EdgeReference.self, forKey: .whole))
        case .parameter:
            try container.validateOnlyExpectedKeys([.kind, .parameter], in: decoder)
            self = .parameter(try container.decode(EdgeParameterReference.self, forKey: .parameter))
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
        }
    }

    public func validate() throws {
        switch self {
        case let .whole(reference):
            try reference.validate()
        case let .parameter(reference):
            try reference.validate()
        }
    }
}

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

public struct CurveCenterReference: Codable, Hashable, Sendable {
    public var curve: CurveOutputReference

    public init(curve: CurveOutputReference) {
        self.curve = curve
    }

    public func validate() throws {
        try curve.validate()
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
    case center(CurveCenterReference)
    case span(CurveSpanReference)
    case controlPoint(CurveControlPointReference)
    case knot(CurveKnotReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case whole
        case parameter
        case center
        case span
        case controlPoint
        case knot
    }

    private enum Kind: String, Codable {
        case whole
        case parameter
        case center
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
        case .center:
            try container.validateOnlyExpectedKeys([.kind, .center], in: decoder)
            self = .center(try container.decode(CurveCenterReference.self, forKey: .center))
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
        case let .center(reference):
            try container.encode(Kind.center, forKey: .kind)
            try container.encode(reference, forKey: .center)
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
        case let .center(reference):
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

public enum SurfaceParameterDirection: String, Codable, Hashable, Sendable {
    case u
    case v
}

public struct SurfaceReference: Codable, Hashable, Sendable {
    public var faceName: PersistentName

    public init(faceName: PersistentName) {
        self.faceName = faceName
    }

    public func validate() throws {
        try faceName.validate()
    }
}

public struct SurfaceParameterReference: Codable, Hashable, Sendable {
    public var surface: SurfaceReference
    public var u: Double
    public var v: Double

    public init(surface: SurfaceReference, u: Double, v: Double) {
        self.surface = surface
        self.u = u
        self.v = v
    }

    public func validate() throws {
        try surface.validate()
        guard u.isFinite else {
            throw GeometryError.invalidCoordinate(u)
        }
        guard v.isFinite else {
            throw GeometryError.invalidCoordinate(v)
        }
    }
}

public struct SurfaceSpanReference: Codable, Hashable, Sendable {
    public var surface: SurfaceReference
    public var direction: SurfaceParameterDirection
    public var spanIndex: Int

    public init(
        surface: SurfaceReference,
        direction: SurfaceParameterDirection,
        spanIndex: Int
    ) {
        self.surface = surface
        self.direction = direction
        self.spanIndex = spanIndex
    }

    public func validate() throws {
        try surface.validate()
        guard spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface span reference index must not be negative.")
        }
    }
}

public struct SurfaceControlPointReference: Codable, Hashable, Sendable {
    public var surface: SurfaceReference
    public var uIndex: Int
    public var vIndex: Int

    public init(surface: SurfaceReference, uIndex: Int, vIndex: Int) {
        self.surface = surface
        self.uIndex = uIndex
        self.vIndex = vIndex
    }

    public func validate() throws {
        try surface.validate()
        guard uIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface control point U index must not be negative.")
        }
        guard vIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface control point V index must not be negative.")
        }
    }
}

public struct SurfaceKnotReference: Codable, Hashable, Sendable {
    public var surface: SurfaceReference
    public var direction: SurfaceParameterDirection
    public var knotIndex: Int

    public init(
        surface: SurfaceReference,
        direction: SurfaceParameterDirection,
        knotIndex: Int
    ) {
        self.surface = surface
        self.direction = direction
        self.knotIndex = knotIndex
    }

    public func validate() throws {
        try surface.validate()
        guard knotIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface knot reference index must not be negative.")
        }
    }
}

public struct SurfaceTrimReference: Codable, Hashable, Sendable {
    public var surface: SurfaceReference
    public var loopIndex: Int
    public var edgeIndex: Int

    public init(surface: SurfaceReference, loopIndex: Int, edgeIndex: Int) {
        self.surface = surface
        self.loopIndex = loopIndex
        self.edgeIndex = edgeIndex
    }

    public func validate() throws {
        try surface.validate()
        guard loopIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim loop index must not be negative.")
        }
        guard edgeIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim edge index must not be negative.")
        }
    }
}

public struct SurfaceTrimSpanReference: Codable, Hashable, Sendable {
    public var trim: SurfaceTrimReference
    public var spanIndex: Int

    public init(trim: SurfaceTrimReference, spanIndex: Int) {
        self.trim = trim
        self.spanIndex = spanIndex
    }

    public func validate() throws {
        try trim.validate()
        guard spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim span reference index must not be negative.")
        }
    }
}

public struct SurfaceTrimKnotReference: Codable, Hashable, Sendable {
    public var trim: SurfaceTrimReference
    public var knotIndex: Int

    public init(trim: SurfaceTrimReference, knotIndex: Int) {
        self.trim = trim
        self.knotIndex = knotIndex
    }

    public func validate() throws {
        try trim.validate()
        guard knotIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim knot reference index must not be negative.")
        }
    }
}

public enum SurfaceSubobjectReference: Codable, Hashable, Sendable {
    case whole(SurfaceReference)
    case parameter(SurfaceParameterReference)
    case span(SurfaceSpanReference)
    case controlPoint(SurfaceControlPointReference)
    case knot(SurfaceKnotReference)
    case trim(SurfaceTrimReference)
    case trimSpan(SurfaceTrimSpanReference)
    case trimKnot(SurfaceTrimKnotReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case whole
        case parameter
        case span
        case controlPoint
        case knot
        case trim
        case trimSpan
        case trimKnot
    }

    private enum Kind: String, Codable {
        case whole
        case parameter
        case span
        case controlPoint
        case knot
        case trim
        case trimSpan
        case trimKnot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .whole:
            try container.validateOnlyExpectedKeys([.kind, .whole], in: decoder)
            self = .whole(try container.decode(SurfaceReference.self, forKey: .whole))
        case .parameter:
            try container.validateOnlyExpectedKeys([.kind, .parameter], in: decoder)
            self = .parameter(try container.decode(SurfaceParameterReference.self, forKey: .parameter))
        case .span:
            try container.validateOnlyExpectedKeys([.kind, .span], in: decoder)
            self = .span(try container.decode(SurfaceSpanReference.self, forKey: .span))
        case .controlPoint:
            try container.validateOnlyExpectedKeys([.kind, .controlPoint], in: decoder)
            self = .controlPoint(try container.decode(SurfaceControlPointReference.self, forKey: .controlPoint))
        case .knot:
            try container.validateOnlyExpectedKeys([.kind, .knot], in: decoder)
            self = .knot(try container.decode(SurfaceKnotReference.self, forKey: .knot))
        case .trim:
            try container.validateOnlyExpectedKeys([.kind, .trim], in: decoder)
            self = .trim(try container.decode(SurfaceTrimReference.self, forKey: .trim))
        case .trimSpan:
            try container.validateOnlyExpectedKeys([.kind, .trimSpan], in: decoder)
            self = .trimSpan(try container.decode(SurfaceTrimSpanReference.self, forKey: .trimSpan))
        case .trimKnot:
            try container.validateOnlyExpectedKeys([.kind, .trimKnot], in: decoder)
            self = .trimKnot(try container.decode(SurfaceTrimKnotReference.self, forKey: .trimKnot))
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
        case let .trim(reference):
            try container.encode(Kind.trim, forKey: .kind)
            try container.encode(reference, forKey: .trim)
        case let .trimSpan(reference):
            try container.encode(Kind.trimSpan, forKey: .kind)
            try container.encode(reference, forKey: .trimSpan)
        case let .trimKnot(reference):
            try container.encode(Kind.trimKnot, forKey: .kind)
            try container.encode(reference, forKey: .trimKnot)
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
        case let .trim(reference):
            try reference.validate()
        case let .trimSpan(reference):
            try reference.validate()
        case let .trimKnot(reference):
            try reference.validate()
        }
    }
}

public enum SelectionReference: Codable, Hashable, Sendable {
    case subshape(SubshapeID)
    case edge(EdgeSubobjectReference)
    case curve(CurveSubobjectReference)
    case sketchPoint(SketchPointSelectionReference)
    case surface(SurfaceSubobjectReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case subshape
        case edge
        case curve
        case sketchPoint
        case surface
    }

    private enum Kind: String, Codable {
        case subshape
        case edge
        case curve
        case sketchPoint
        case surface
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .subshape:
            try container.validateOnlyExpectedKeys([.kind, .subshape], in: decoder)
            self = .subshape(try container.decode(SubshapeID.self, forKey: .subshape))
        case .edge:
            try container.validateOnlyExpectedKeys([.kind, .edge], in: decoder)
            self = .edge(try container.decode(EdgeSubobjectReference.self, forKey: .edge))
        case .curve:
            try container.validateOnlyExpectedKeys([.kind, .curve], in: decoder)
            self = .curve(try container.decode(CurveSubobjectReference.self, forKey: .curve))
        case .sketchPoint:
            try container.validateOnlyExpectedKeys([.kind, .sketchPoint], in: decoder)
            self = .sketchPoint(try container.decode(SketchPointSelectionReference.self, forKey: .sketchPoint))
        case .surface:
            try container.validateOnlyExpectedKeys([.kind, .surface], in: decoder)
            self = .surface(try container.decode(SurfaceSubobjectReference.self, forKey: .surface))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .subshape(subshapeID):
            try container.encode(Kind.subshape, forKey: .kind)
            try container.encode(subshapeID, forKey: .subshape)
        case let .edge(reference):
            try container.encode(Kind.edge, forKey: .kind)
            try container.encode(reference, forKey: .edge)
        case let .curve(reference):
            try container.encode(Kind.curve, forKey: .kind)
            try container.encode(reference, forKey: .curve)
        case let .sketchPoint(reference):
            try container.encode(Kind.sketchPoint, forKey: .kind)
            try container.encode(reference, forKey: .sketchPoint)
        case let .surface(reference):
            try container.encode(Kind.surface, forKey: .kind)
            try container.encode(reference, forKey: .surface)
        }
    }

    public func validate() throws {
        switch self {
        case let .subshape(subshapeID):
            guard subshapeID.isValid else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    subshapeID: subshapeID,
                    message: "Subshape selection identity is invalid."
                )
            }
        case let .edge(reference):
            try reference.validate()
        case let .curve(reference):
            try reference.validate()
        case let .sketchPoint(reference):
            try reference.validate()
        case let .surface(reference):
            try reference.validate()
        }
    }
}
