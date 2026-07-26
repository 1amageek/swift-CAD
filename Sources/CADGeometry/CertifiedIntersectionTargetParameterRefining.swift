import CADCore

protocol CertifiedIntersectionTargetParameterRefining: Sendable {
    func refinedParameter(
        initialParameter: Double,
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        restrictedTo range: ScalarInterval?,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> (parameter: Double, iterations: Int)
}
