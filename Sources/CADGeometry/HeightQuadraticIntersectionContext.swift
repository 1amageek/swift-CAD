import CADCore

protocol HeightQuadraticIntersectionContext: Sendable {
    var sourceSurface: Surface3D { get }
    var targetSurface: Surface3D { get }
    var sourceEquation: TrigonometricHeightQuadratic { get }
    var targetEquation: TrigonometricHeightQuadratic { get }
    var characteristicLength: Double { get }

    func candidatePoints(
        atAngle angle: Double,
        tolerance: ModelingTolerance
    ) throws -> [Point3D]
}
