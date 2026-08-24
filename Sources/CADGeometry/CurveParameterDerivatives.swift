import CADCore

/// Position and first/second parameter derivatives without regularity or curvature analysis.
public struct CurveParameterDerivatives: Sendable, Hashable {
    public let position: Point3D
    public let firstDerivative: Vector3D
    public let secondDerivative: Vector3D

    public init(
        position: Point3D,
        firstDerivative: Vector3D,
        secondDerivative: Vector3D
    ) {
        self.position = position
        self.firstDerivative = firstDerivative
        self.secondDerivative = secondDerivative
    }
}
