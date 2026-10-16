import CADCore
import CADGeometry

public struct EdgeReference: Hashable, Sendable {
    public var subshape: StableSubshapeReference

    public init(subshape: StableSubshapeReference) {
        self.subshape = subshape
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try subshape.validate(using: &execution)
    }
}

public struct EdgeParameterReference: Hashable, Sendable {
    public var edge: EdgeReference
    public var parameter: Double

    public init(edge: EdgeReference, parameter: Double) {
        self.edge = edge
        self.parameter = parameter
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try edge.validate(using: &execution)
        guard parameter.isFinite else {
            throw GeometryError.invalidCoordinate(parameter)
        }
    }
}

public enum EdgeSubobjectReference: Hashable, Sendable {
    case whole(EdgeReference)
    case parameter(EdgeParameterReference)

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case whole
        case parameter
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case whole
        case parameter
    }
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
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
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch self {
        case let .whole(reference):
            try reference.validate(using: &execution)
        case let .parameter(reference):
            try reference.validate(using: &execution)
        }
    }
}

public struct CurveOutputReference: Hashable, Sendable {
    public var featureID: FeatureID
    public var curveIndex: Int

    public init(featureID: FeatureID, curveIndex: Int = 0) {
        self.featureID = featureID
        self.curveIndex = curveIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard curveIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve output reference index must not be negative.")
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case featureID
        case curveIndex
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .curveIndex], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        curveIndex = try container.decode(Int.self, forKey: .curveIndex)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
        try container.encode(curveIndex, forKey: .curveIndex)
    }
#endif
}

public struct CurveParameterReference: Hashable, Sendable {
    public var curve: CurveOutputReference
    public var parameter: Double

    public init(curve: CurveOutputReference, parameter: Double) {
        self.curve = curve
        self.parameter = parameter
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try curve.validate(using: &execution)
        guard parameter.isFinite else {
            throw GeometryError.invalidCoordinate(parameter)
        }
    }
}

public struct CurveCenterReference: Hashable, Sendable {
    public var curve: CurveOutputReference

    public init(curve: CurveOutputReference) {
        self.curve = curve
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try curve.validate(using: &execution)
    }
}

public struct CurveSpanReference: Hashable, Sendable {
    public var curve: CurveOutputReference
    public var spanIndex: Int

    public init(curve: CurveOutputReference, spanIndex: Int) {
        self.curve = curve
        self.spanIndex = spanIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try curve.validate(using: &execution)
        guard spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve span reference index must not be negative.")
        }
    }
}

public struct CurveControlPointReference: Hashable, Sendable {
    public var curve: CurveOutputReference
    public var controlPointIndex: Int

    public init(curve: CurveOutputReference, controlPointIndex: Int) {
        self.curve = curve
        self.controlPointIndex = controlPointIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try curve.validate(using: &execution)
        guard controlPointIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve control point reference index must not be negative.")
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case curve
        case controlPointIndex
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curve, .controlPointIndex], in: decoder)
        curve = try container.decode(CurveOutputReference.self, forKey: .curve)
        controlPointIndex = try container.decode(Int.self, forKey: .controlPointIndex)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encode(controlPointIndex, forKey: .controlPointIndex)
    }
#endif
}

public struct CurveKnotReference: Hashable, Sendable {
    public var curve: CurveOutputReference
    public var knotIndex: Int

    public init(curve: CurveOutputReference, knotIndex: Int) {
        self.curve = curve
        self.knotIndex = knotIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try curve.validate(using: &execution)
        guard knotIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Curve knot reference index must not be negative.")
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case curve
        case knotIndex
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curve, .knotIndex], in: decoder)
        curve = try container.decode(CurveOutputReference.self, forKey: .curve)
        knotIndex = try container.decode(Int.self, forKey: .knotIndex)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curve, forKey: .curve)
        try container.encode(knotIndex, forKey: .knotIndex)
    }
#endif
}

public enum CurveSubobjectReference: Hashable, Sendable {
    case whole(CurveOutputReference)
    case parameter(CurveParameterReference)
    case center(CurveCenterReference)
    case span(CurveSpanReference)
    case controlPoint(CurveControlPointReference)
    case knot(CurveKnotReference)

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case whole
        case parameter
        case center
        case span
        case controlPoint
        case knot
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case whole
        case parameter
        case center
        case span
        case controlPoint
        case knot
    }
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
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
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch self {
        case let .whole(reference):
            try reference.validate(using: &execution)
        case let .parameter(reference):
            try reference.validate(using: &execution)
        case let .center(reference):
            try reference.validate(using: &execution)
        case let .span(reference):
            try reference.validate(using: &execution)
        case let .controlPoint(reference):
            try reference.validate(using: &execution)
        case let .knot(reference):
            try reference.validate(using: &execution)
        }
    }
}

public struct SurfaceReference: Hashable, Sendable {
    public var subshape: StableSubshapeReference

    public init(subshape: StableSubshapeReference) {
        self.subshape = subshape
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try subshape.validate(using: &execution)
    }
}

public struct SurfaceParameterReference: Hashable, Sendable {
    public var surface: SurfaceReference
    public var u: Double
    public var v: Double

    public init(surface: SurfaceReference, u: Double, v: Double) {
        self.surface = surface
        self.u = u
        self.v = v
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try surface.validate(using: &execution)
        guard u.isFinite else {
            throw GeometryError.invalidCoordinate(u)
        }
        guard v.isFinite else {
            throw GeometryError.invalidCoordinate(v)
        }
    }
}

public struct SurfaceSpanReference: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try surface.validate(using: &execution)
        guard spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface span reference index must not be negative.")
        }
    }
}

public struct SurfaceControlPointReference: Hashable, Sendable {
    public var surface: SurfaceReference
    public var uIndex: Int
    public var vIndex: Int

    public init(surface: SurfaceReference, uIndex: Int, vIndex: Int) {
        self.surface = surface
        self.uIndex = uIndex
        self.vIndex = vIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try surface.validate(using: &execution)
        guard uIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface control point U index must not be negative.")
        }
        guard vIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface control point V index must not be negative.")
        }
    }
}

public struct SurfaceKnotReference: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try surface.validate(using: &execution)
        guard knotIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface knot reference index must not be negative.")
        }
    }
}

public struct SurfaceTrimReference: Hashable, Sendable {
    public var surface: SurfaceReference
    public var loopIndex: Int
    public var edgeIndex: Int

    public init(surface: SurfaceReference, loopIndex: Int, edgeIndex: Int) {
        self.surface = surface
        self.loopIndex = loopIndex
        self.edgeIndex = edgeIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try surface.validate(using: &execution)
        guard loopIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim loop index must not be negative.")
        }
        guard edgeIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim edge index must not be negative.")
        }
    }
}

public struct SurfaceTrimSpanReference: Hashable, Sendable {
    public var trim: SurfaceTrimReference
    public var spanIndex: Int

    public init(trim: SurfaceTrimReference, spanIndex: Int) {
        self.trim = trim
        self.spanIndex = spanIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try trim.validate(using: &execution)
        guard spanIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim span reference index must not be negative.")
        }
    }
}

public struct SurfaceTrimKnotReference: Hashable, Sendable {
    public var trim: SurfaceTrimReference
    public var knotIndex: Int

    public init(trim: SurfaceTrimReference, knotIndex: Int) {
        self.trim = trim
        self.knotIndex = knotIndex
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try trim.validate(using: &execution)
        guard knotIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface trim knot reference index must not be negative.")
        }
    }
}

public enum SurfaceSubobjectReference: Hashable, Sendable {
    case whole(SurfaceReference)
    case parameter(SurfaceParameterReference)
    case span(SurfaceSpanReference)
    case controlPoint(SurfaceControlPointReference)
    case knot(SurfaceKnotReference)
    case trim(SurfaceTrimReference)
    case trimSpan(SurfaceTrimSpanReference)
    case trimKnot(SurfaceTrimKnotReference)

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
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
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch self {
        case let .whole(reference):
            try reference.validate(using: &execution)
        case let .parameter(reference):
            try reference.validate(using: &execution)
        case let .span(reference):
            try reference.validate(using: &execution)
        case let .controlPoint(reference):
            try reference.validate(using: &execution)
        case let .knot(reference):
            try reference.validate(using: &execution)
        case let .trim(reference):
            try reference.validate(using: &execution)
        case let .trimSpan(reference):
            try reference.validate(using: &execution)
        case let .trimKnot(reference):
            try reference.validate(using: &execution)
        }
    }
}

public enum SelectionReference: Hashable, Sendable {
    case subshape(StableSubshapeReference)
    case edge(EdgeSubobjectReference)
    case curve(CurveSubobjectReference)
    case sketchPoint(SketchPointSelectionReference)
    case surface(SurfaceSubobjectReference)

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case subshape
        case edge
        case curve
        case sketchPoint
        case surface
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case subshape
        case edge
        case curve
        case sketchPoint
        case surface
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .subshape:
            try container.validateOnlyExpectedKeys([.kind, .subshape], in: decoder)
            self = .subshape(try container.decode(StableSubshapeReference.self, forKey: .subshape))
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
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .subshape(reference):
            try container.encode(Kind.subshape, forKey: .kind)
            try container.encode(reference, forKey: .subshape)
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
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch self {
        case let .subshape(reference):
            try reference.validate(using: &execution)
        case let .edge(reference):
            try reference.validate(using: &execution)
        case let .curve(reference):
            try reference.validate(using: &execution)
        case let .sketchPoint(reference):
            try reference.validate()
        case let .surface(reference):
            try reference.validate(using: &execution)
        }
    }
}

#if !hasFeature(Embedded)
extension EdgeReference: Codable {}
extension EdgeParameterReference: Codable {}
extension EdgeSubobjectReference: Codable {}
extension CurveOutputReference: Codable {}
extension CurveParameterReference: Codable {}
extension CurveCenterReference: Codable {}
extension CurveSpanReference: Codable {}
extension CurveControlPointReference: Codable {}
extension CurveKnotReference: Codable {}
extension CurveSubobjectReference: Codable {}
extension SurfaceReference: Codable {}
extension SurfaceParameterReference: Codable {}
extension SurfaceSpanReference: Codable {}
extension SurfaceControlPointReference: Codable {}
extension SurfaceKnotReference: Codable {}
extension SurfaceTrimReference: Codable {}
extension SurfaceTrimSpanReference: Codable {}
extension SurfaceTrimKnotReference: Codable {}
extension SurfaceSubobjectReference: Codable {}
extension SelectionReference: Codable {}
#endif
