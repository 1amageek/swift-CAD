import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.AnalyticSurface3D
import SourceIssuer
#endif

/// Retains the original primitive and its family-issued binary image frame.
public struct OriginalAnalyticPrimitiveSnapshot: OriginalPrimitiveImageReading {
    public let original: AnalyticSurface3D
    public let imageKind: OriginalPrimitiveImageKind
    public let majorRadius: Double
    public let minorRadius: Double
    let origin: Point3D
    let first: Vector3D
    let second: Vector3D
    let axis: Vector3D
    init(original: AnalyticSurface3D, kind: OriginalPrimitiveImageKind, origin: Point3D,
        first: Vector3D, second: Vector3D, axis: Vector3D, major: Double, minor: Double) {
        self.original = original; imageKind = kind; self.origin = origin
        self.first = first; self.second = second; self.axis = axis
        majorRadius = major; minorRadius = minor
    }
    public func center(in axis: Int) -> Double {
        switch axis { case 0: return origin.x; case 1: return origin.y; default: return origin.z }
    }
    public func frame(row: Int, column: Int) -> Double {
        let value = column == 0 ? first : column == 1 ? second : axis
        switch row { case 0: return value.x; case 1: return value.y; default: return value.z }
    }
}
