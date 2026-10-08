import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.AnalyticSurface3D
import SourceIssuer
#endif

/// Original cone authority and its original binary chart frame.
public struct OriginalAnalyticConeSnapshot: OriginalConeImageReading {
    public let original: AnalyticSurface3D
    public let physicalHalfAngle: Double
    let apex: Point3D
    let first: Vector3D
    let second: Vector3D
    let axis: Vector3D
    init(original: AnalyticSurface3D, halfAngle: Double, apex: Point3D,
        first: Vector3D, second: Vector3D, axis: Vector3D) {
        self.original = original; physicalHalfAngle = halfAngle; self.apex = apex
        self.first = first; self.second = second; self.axis = axis
    }
    public func center(in axis: Int) -> Double {
        switch axis { case 0: return apex.x; case 1: return apex.y; default: return apex.z }
    }
    public func frame(row: Int, column: Int) -> Double {
        let value = column == 0 ? first : column == 1 ? second : axis
        switch row { case 0: return value.x; case 1: return value.y; default: return value.z }
    }
}
