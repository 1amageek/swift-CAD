import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Curve3D
import L0
import SourceIssuer
#endif

/// The exact original line fields; the authored direction keeps its original scale.
public struct OriginalLinearCurveSnapshot: OriginalLinearSourceReading {
    public let original: Curve3D
    public let origin: Point3D
    public let direction: Vector3D
    init(original: Curve3D, origin: Point3D, direction: Vector3D) {
        self.original = original; self.origin = origin; self.direction = direction
    }
    public func originCoordinate(in axis: Int) -> Double { axis == 0 ? origin.x : axis == 1 ? origin.y : origin.z }
    public func directionCoordinate(in axis: Int) -> Double { axis == 0 ? direction.x : axis == 1 ? direction.y : direction.z }
}
