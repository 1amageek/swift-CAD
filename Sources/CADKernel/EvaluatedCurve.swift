import CADCore
import CADIR

public struct EvaluatedCurve: Sendable, Hashable {
    public var sourceFeatureID: FeatureID
    public var source: EvaluatedCurveSource
    public var kind: EvaluatedCurveKind
    public var points: [Point3D]
    public var isClosed: Bool
    public var exactCurve: Curve3D?

    public var parameterDomain: ParameterDomain {
        exactCurve?.parameterDomain ?? .closed(0.0, 1.0)
    }

    public init(
        sourceFeatureID: FeatureID,
        source: EvaluatedCurveSource,
        kind: EvaluatedCurveKind,
        points: [Point3D],
        isClosed: Bool = false,
        exactCurve: Curve3D? = nil
    ) {
        self.sourceFeatureID = sourceFeatureID
        self.source = source
        self.kind = kind
        self.points = points
        self.isClosed = isClosed
        self.exactCurve = exactCurve
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        guard points.count >= 2 else {
            throw SketchError.unsupportedEntity("Evaluated curves require at least two points.")
        }
        for point in points {
            try point.validate()
        }
        for index in 0..<(points.count - 1) {
            guard (points[index + 1] - points[index]).length > tolerance.distance else {
                throw SketchError.unsupportedEntity("Evaluated curves must not contain degenerate spans.")
            }
        }
        if isClosed {
            guard let first = points.first,
                  let last = points.last,
                  first.isApproximatelyEqual(to: last, tolerance: tolerance.distance) else {
                throw SketchError.openProfile
            }
        }
    }
}

public enum EvaluatedCurveSource: Sendable, Hashable {
    case sketchEntity(SketchEntityID)
    case generatedFeature
}

public enum EvaluatedCurveKind: Sendable, Hashable {
    case line
    case circle
    case arc
    case spline
}
