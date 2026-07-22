import CADCore
import CADIR

public struct CurveDirectionalProjectionResult: Codable, Sendable, Hashable {
    public var sourcePoint: Point3D
    public var direction: Vector3D
    public var signedDistanceAlongDirection: Double
    public var linePoint: Point3D
    public var parameterReference: CurveParameterReference
    public var projectedPoint: Point3D
    public var lineResidual: Vector3D
    public var lineDistance: Double
    public var queryPoint: CurveQueryPoint
    public var iterations: Int
    public var converged: Bool

    public var isExact: Bool {
        queryPoint.isExact
    }

    public init(
        sourcePoint: Point3D,
        direction: Vector3D,
        signedDistanceAlongDirection: Double,
        queryPoint: CurveQueryPoint,
        iterations: Int,
        converged: Bool
    ) {
        self.sourcePoint = sourcePoint
        self.direction = direction
        self.signedDistanceAlongDirection = signedDistanceAlongDirection
        self.linePoint = sourcePoint + direction * signedDistanceAlongDirection
        self.parameterReference = queryPoint.reference
        self.projectedPoint = queryPoint.point
        self.lineResidual = queryPoint.point - self.linePoint
        self.lineDistance = self.lineResidual.length
        self.queryPoint = queryPoint
        self.iterations = iterations
        self.converged = converged
    }
}
