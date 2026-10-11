import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Surface3D
import SourceIssuer
#endif

/// N+origin authority; an explicit authored U direction is a different capability.
public struct OriginalPlaneSnapshot: OriginalPlaneSourceReading {
    public let original: Surface3D
    public let origin: Point3D
    public let normal: Vector3D
    public func originCoordinate(in axis: Int) -> Double { axis == 0 ? origin.x : axis == 1 ? origin.y : origin.z }
    public func normalCoordinate(in axis: Int) -> Double { axis == 0 ? normal.x : axis == 1 ? normal.y : normal.z }
}
