import CADCore

public struct CertifiedImplicitIntersectionDifferential: Sendable, Hashable {
    public let position: Point3D
    public let firstDerivative: Vector3D
    public let secondDerivative: Vector3D
    public let parameters: SurfaceIntersectionParameterPair
    public let firstParameterDerivatives: SurfaceIntersectionParameterVector
    public let secondParameterDerivatives: SurfaceIntersectionParameterVector

    public init(
        position: Point3D,
        firstDerivative: Vector3D,
        secondDerivative: Vector3D,
        parameters: SurfaceIntersectionParameterPair,
        firstParameterDerivatives: SurfaceIntersectionParameterVector,
        secondParameterDerivatives: SurfaceIntersectionParameterVector
    ) {
        self.position = position
        self.firstDerivative = firstDerivative
        self.secondDerivative = secondDerivative
        self.parameters = parameters
        self.firstParameterDerivatives = firstParameterDerivatives
        self.secondParameterDerivatives = secondParameterDerivatives
    }
}
