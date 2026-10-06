import CADGeometry

public protocol BRepDrawingCurveLinearizing: Sendable {
    func linearize(_ curve: OrthographicProjectedCurve, from start: Double, to end: Double,
                   maximumDeviation: Double, usage: inout DrawingExchangeUsage) throws -> BRepDrawingCurvePath
}
