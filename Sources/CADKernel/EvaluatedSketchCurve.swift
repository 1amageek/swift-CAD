import CADCore
import CADIR

public struct EvaluatedSketchCurve: Sendable, Hashable {
    public var sourceFeatureID: FeatureID
    public var entityID: SketchEntityID
    public var kind: EvaluatedSketchCurveKind
    public var points: [Point3D]
    public var isClosed: Bool

    public init(
        sourceFeatureID: FeatureID,
        entityID: SketchEntityID,
        kind: EvaluatedSketchCurveKind,
        points: [Point3D],
        isClosed: Bool = false
    ) {
        self.sourceFeatureID = sourceFeatureID
        self.entityID = entityID
        self.kind = kind
        self.points = points
        self.isClosed = isClosed
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        guard points.count >= 2 else {
            throw SketchError.unsupportedEntity("Sketch curves require at least two evaluated points.")
        }
        for point in points {
            try point.validate()
        }
        for index in 0..<(points.count - 1) {
            guard (points[index + 1] - points[index]).length > tolerance.distance else {
                throw SketchError.unsupportedEntity("Sketch curves must not contain degenerate spans.")
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

public enum EvaluatedSketchCurveKind: Sendable, Hashable {
    case line
    case circle
    case arc
    case spline
}
