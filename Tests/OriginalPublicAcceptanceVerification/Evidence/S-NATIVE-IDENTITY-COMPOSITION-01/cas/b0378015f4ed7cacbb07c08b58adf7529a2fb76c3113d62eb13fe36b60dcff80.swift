import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import struct CADGeometry.BSplineCurve3D
import SourceIssuer
#endif

extension BSplineCurve3D: OriginalBSplineSourceReading {
    public var parameterCount: Int { 1 }
    public func degree(in axis: Int) -> Int { degree }
    public func controlCount(in axis: Int) -> Int { controlPointCount }
    public func knotCount(in axis: Int) -> Int { knots.count }
    public func isPeriodic(in axis: Int) -> Bool { isPeriodic }
    public func knot(at index: Int, in axis: Int) -> Double { knots[index] }
    public func coordinate(ofControl index: Int, in axis: Int) -> Double {
        let point = controlPoints[index]
        switch axis { case 0: return point.x; case 1: return point.y; default: return point.z }
    }
    public func weight(ofControl index: Int) -> Double { weights[index] }
}
