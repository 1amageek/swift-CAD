import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import struct CADGeometry.BSplineSurface3D
import SourceIssuer
#endif

extension BSplineSurface3D: OriginalBSplineSourceReading {
    public var parameterCount: Int { 2 }
    public func degree(in axis: Int) -> Int { axis == 0 ? uDegree : vDegree }
    public func controlCount(in axis: Int) -> Int { axis == 0 ? uControlPointCount : vControlPointCount }
    public func knotCount(in axis: Int) -> Int { axis == 0 ? uKnots.count : vKnots.count }
    public func isPeriodic(in axis: Int) -> Bool { axis == 0 ? isUPeriodic : isVPeriodic }
    public func knot(at index: Int, in axis: Int) -> Double { axis == 0 ? uKnots[index] : vKnots[index] }
    public func coordinate(ofControl index: Int, in axis: Int) -> Double {
        let point = controlPoints[index / uControlPointCount][index % uControlPointCount]
        switch axis { case 0: return point.x; case 1: return point.y; default: return point.z }
    }
    public func weight(ofControl index: Int) -> Double {
        weights[index / uControlPointCount][index % uControlPointCount]
    }
}
