import CADCore
import CADIR

public struct CurveProjectionResult: Sendable, Hashable {
    public var sourcePoint: Point3D
    public var parameterReference: CurveParameterReference
    public var projectedPoint: Point3D
    public var residual: Vector3D
    public var distance: Double
    public var queryPoint: CurveQueryPoint
    public var iterations: Int
    public var converged: Bool

    public var isExact: Bool {
        queryPoint.isExact
    }

    public init(
        sourcePoint: Point3D,
        queryPoint: CurveQueryPoint,
        iterations: Int,
        converged: Bool
    ) {
        self.sourcePoint = sourcePoint
        self.parameterReference = queryPoint.reference
        self.projectedPoint = queryPoint.point
        self.residual = sourcePoint - queryPoint.point
        self.distance = self.residual.length
        self.queryPoint = queryPoint
        self.iterations = iterations
        self.converged = converged
    }
}
