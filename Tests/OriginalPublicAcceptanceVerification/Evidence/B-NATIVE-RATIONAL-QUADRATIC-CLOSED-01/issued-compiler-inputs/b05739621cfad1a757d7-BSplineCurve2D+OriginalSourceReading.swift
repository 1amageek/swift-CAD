import CADCore

/// Original UV controls embedded homogeneously without a fitted spatial curve.
extension BSplineCurve2D: OriginalBSplineSourceReading {
    public var parameterCount: Int { 1 }
    public func degree(in axis: Int) -> Int { degree }
    public func controlCount(in axis: Int) -> Int { controlPoints.count }
    public func knotCount(in axis: Int) -> Int { knots.count }
    public func isPeriodic(in axis: Int) -> Bool { false }
    public func knot(at index: Int, in axis: Int) -> Double { knots[index] }
    public func coordinate(ofControl index: Int, in axis: Int) -> Double {
        switch axis { case 0: return controlPoints[index].x
        case 1: return controlPoints[index].y; default: return 0 }
    }
    public func weight(ofControl index: Int) -> Double { weights[index] }
}
