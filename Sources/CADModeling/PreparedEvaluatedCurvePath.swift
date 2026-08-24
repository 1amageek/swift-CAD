import CADCore
import CADGeometry

/// A reusable path parameterization prepared from canonical curve geometry.
public struct PreparedEvaluatedCurvePath: Sendable {
    enum Storage: Sendable {
        case exact(
            curve: Curve3D,
            parameterization: any CurveArcLengthParameterization
        )
        case polyline(
            points: [Point3D],
            cumulativeLengths: [Double]
        )
    }

    public let origin: Point3D
    public let totalLength: Double
    let storage: Storage

    init(
        origin: Point3D,
        totalLength: Double,
        storage: Storage
    ) {
        self.origin = origin
        self.totalLength = totalLength
        self.storage = storage
    }
}
