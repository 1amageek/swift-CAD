import CADCore

public struct CurveEvaluationSample: Codable, Equatable, Sendable {
    public var parameter: Double
    public var point: Point2D
    public var tangent: Point2D
    public var normal: Point2D
    public var curvature: Double

    public init(
        parameter: Double,
        point: Point2D,
        tangent: Point2D,
        normal: Point2D,
        curvature: Double
    ) {
        self.parameter = parameter
        self.point = point
        self.tangent = tangent
        self.normal = normal
        self.curvature = curvature
    }
}
